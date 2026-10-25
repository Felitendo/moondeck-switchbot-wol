#!/usr/bin/env python3
"""Pairs the Deck and the PC over the network, with no code to copy.

    pair.py listen PORT TIMEOUT          on the Deck: wait for the PC
    pair.py scan PORT TIMEOUT TARGET...  on the PC: look for a Deck that waits
    pair.py send ADDRESS PORT            on the PC: send MSW_PAIR_CODE to it

A TARGET is an address, or this PC's address with its prefix, like
192.168.2.10/24. Then the whole network is tried, or the /24 around the
address when the network is bigger.

The menus talk to this through lines: events on standard output, the user's
answers on standard input.

    listen:  PEER <digits> <address> <name>   answer yes or no
             DATA <pairing code>              answer ok once it is saved
             DONE (the PC has the answer) | CANCELLED | TIMEOUT | FAILED <why>
    scan:    FOUND <address> <name>, one line per Deck, or NONE
    send:    PEER <digits> <name>             answer yes or no
             OK | NO | ERROR | FAILED <why>

On the wire, the PC connects to the Deck:

    Deck:  MSW-PAIR 1 <name>
    PC:    COMMIT <sha256 of its key> <name>
    Deck:  KEY <its key>
    PC:    KEY <its key>
    PC:    DATA <pairing code, encrypted> <tag>    once its user said yes
    Deck:  OK | NO | ERROR

Diffie-Hellman (RFC 3526, group 14) gives both ends the same key, and
listening in does not tell anybody what it is. Both ends show six digits
made from that key. Somebody in the middle would have a different key with
each end, so the digits would not match. The PC commits to its key before it
sees the Deck's, so nobody can try keys until the digits match by chance.
The pairing code goes over encrypted, with HMAC-SHA256 in counter mode, and
with an HMAC over that.
"""

import base64
import concurrent.futures
import hashlib
import hmac
import ipaddress
import os
import re
import secrets
import socket
import sys
import time

GREETING = "MSW-PAIR 1 "

# RFC 3526, group 14: a 2048 bit safe prime, with 2 as the generator.
P = int(
    "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74"
    "020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F1437"
    "4FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED"
    "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3DC2007CB8A163BF05"
    "98DA48361C55D39A69163FA8FD24CF5F83655D23DCA3AD961C62F356208552BB"
    "9ED529077096966D670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B"
    "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF695581718"
    "3995497CEA956AE515D2261898FA051015728E5A8AACAA68FFFFFFFFFFFFFFFF", 16)
G = 2
KEY_BYTES = 256

# A bigger network is cut down to the /24 around the PC.
MAX_HOSTS = 1024
PROBE_TIMEOUT = 0.7
SWEEP_PAUSE = 2
HANDSHAKE_TIMEOUT = 10
# How long one end waits for the user at the other.
ANSWER_TIMEOUT = 300
# Longer than any line of the protocol.
LINE_LIMIT = 4096


def emit(*fields):
    print(" ".join(str(field) for field in fields), flush=True)


def answer():
    """The user's answer, from the menu."""
    return sys.stdin.readline().strip()


def clean(name):
    """A host name fit for one field of a line."""
    return re.sub(r"[^!-~]", "?", name)[:64] or "?"


def send(stream, line):
    stream.write(line + "\n")
    stream.flush()


def receive(stream):
    """The next line, or "" at the end."""
    return stream.readline(LINE_LIMIT).strip()


def connect(connection):
    return connection.makefile("rw", encoding="ascii", newline="\n")


# --- the key -----------------------------------------------------------------

def keypair():
    private = secrets.randbelow(P - 3) + 2
    return private, pow(G, private, P)


def public_key(line):
    """The key in a KEY line, or None when it is not one."""
    words = line.split(" ")
    if len(words) != 2 or words[0] != "KEY":
        return None
    try:
        value = int(words[1], 16)
    except ValueError:
        return None
    # 1 and P - 1 would give a key anybody can work out.
    return value if 1 < value < P - 1 else None


def commitment(public):
    return hashlib.sha256(public.to_bytes(KEY_BYTES, "big")).hexdigest()


def derive(private, peer, deck, pc):
    """The keys to encrypt and to sign with, and the digits both ends show."""
    shared = pow(peer, private, P).to_bytes(KEY_BYTES, "big")
    both = deck.to_bytes(KEY_BYTES, "big") + pc.to_bytes(KEY_BYTES, "big")
    master = hmac.new(shared, b"msw-pair-1" + both, hashlib.sha256).digest()

    def key(label):
        return hmac.new(master, label, hashlib.sha256).digest()

    digits = int.from_bytes(key(b"digits")[:8], "big") % 1000000
    return key(b"encrypt"), key(b"sign"), "%06d" % digits


def crypt(key, data):
    """HMAC-SHA256 in counter mode. The same call encrypts and decrypts."""
    stream = b"".join(hmac.new(key, block.to_bytes(4, "big"), hashlib.sha256).digest()
                      for block in range(len(data) // 32 + 1))
    return bytes(a ^ b for a, b in zip(data, stream))


def seal(encrypt, sign, text):
    data = crypt(encrypt, text.encode("ascii"))
    tag = hmac.new(sign, data, hashlib.sha256).digest()
    return "%s %s" % (base64.b64encode(data).decode(), base64.b64encode(tag).decode())


def unseal(encrypt, sign, sealed):
    """The text, or None when it was changed on the way."""
    try:
        data, tag = (base64.b64decode(part, validate=True) for part in sealed.split(" "))
    except ValueError:
        return None
    if not hmac.compare_digest(tag, hmac.new(sign, data, hashlib.sha256).digest()):
        return None
    return crypt(encrypt, data).decode("ascii", "replace")


# --- the Deck ----------------------------------------------------------------

def serve(connection, address):
    """One connection. None when it was no PC that wants to pair."""
    connection.settimeout(HANDSHAKE_TIMEOUT)
    with connect(connection) as stream:
        try:
            send(stream, GREETING + clean(socket.gethostname()))
            words = receive(stream).split(" ", 2)
            if len(words) != 3 or words[0] != "COMMIT":
                return None
            private, public = keypair()
            send(stream, "KEY %x" % public)
            peer = public_key(receive(stream))
        except (OSError, UnicodeError):
            return None
        if peer is None or not hmac.compare_digest(words[1], commitment(peer)):
            return None

        encrypt, sign, digits = derive(private, peer, public, peer)
        emit("PEER", digits, address, clean(words[2]))
        if answer() != "yes":
            try:
                send(stream, "NO")
            except OSError:
                pass
            emit("DONE")
            return 1

        connection.settimeout(ANSWER_TIMEOUT)
        try:
            line = receive(stream)
        except (OSError, UnicodeError):
            line = ""
        if not line:
            emit("CANCELLED")
            return 1
        text = unseal(encrypt, sign, line[5:]) if line.startswith("DATA ") else None
        if text is None:
            emit("FAILED", "the PC sent something else")
            return 1

        emit("DATA", text)
        saved = answer() == "ok"
        try:
            send(stream, "OK" if saved else "ERROR")
        except OSError:
            pass
        emit("DONE")
        return 0 if saved else 1


def listen(port, timeout):
    try:
        server = socket.create_server(("", port))
    except OSError as error:
        emit("FAILED", error.strerror or error)
        return 1

    deadline = time.monotonic() + timeout
    with server:
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                emit("TIMEOUT")
                return 1
            server.settimeout(left)
            try:
                connection, peer = server.accept()
            # TimeoutError only since Python 3.10.
            except socket.timeout:
                continue
            with connection:
                result = serve(connection, peer[0])
            if result is not None:
                return result


# --- the PC ------------------------------------------------------------------

def targets(specs):
    """Every address to try, in order and once."""
    addresses = {}
    for spec in specs:
        interface = ipaddress.ip_interface(spec)
        network = interface.network
        if network.num_addresses > MAX_HOSTS:
            network = ipaddress.ip_interface("%s/24" % interface.ip).network
        for host in list(network.hosts()) or [interface.ip]:
            addresses[str(host)] = True
    return list(addresses)


def probe(address, port):
    """The name of the Deck that waits at that address, or None."""
    try:
        with socket.create_connection((address, port), timeout=PROBE_TIMEOUT) as connection:
            connection.settimeout(2)
            with connect(connection) as stream:
                greeting = receive(stream)
    except (OSError, UnicodeError):
        return None
    return clean(greeting[len(GREETING):]) if greeting.startswith(GREETING) else None


def scan(port, timeout, specs):
    addresses = targets(specs)
    deadline = time.monotonic() + timeout
    with concurrent.futures.ThreadPoolExecutor(max_workers=128) as pool:
        while True:
            names = list(pool.map(lambda address: probe(address, port), addresses))
            found = [(address, name) for address, name in zip(addresses, names) if name]
            for address, name in found:
                emit("FOUND", address, name)
            if found:
                return 0
            if time.monotonic() + SWEEP_PAUSE >= deadline:
                emit("NONE")
                return 1
            time.sleep(SWEEP_PAUSE)


def pair(address, port, code):
    try:
        connection = socket.create_connection((address, port), timeout=HANDSHAKE_TIMEOUT)
    except OSError as error:
        emit("FAILED", error.strerror or error)
        return 1

    with connection, connect(connection) as stream:
        try:
            greeting = receive(stream)
            if not greeting.startswith(GREETING):
                emit("FAILED", "no Deck waits at %s" % address)
                return 1
            private, public = keypair()
            send(stream, "COMMIT %s %s" % (commitment(public), clean(socket.gethostname())))
            peer = public_key(receive(stream))
            if peer is None:
                emit("FAILED", "the Deck sent no key")
                return 1
            send(stream, "KEY %x" % public)
        except (OSError, UnicodeError) as error:
            emit("FAILED", error)
            return 1

        encrypt, sign, digits = derive(private, peer, peer, public)
        emit("PEER", digits, clean(greeting[len(GREETING):]))
        if answer() != "yes":
            return 1

        connection.settimeout(ANSWER_TIMEOUT)
        try:
            send(stream, "DATA " + seal(encrypt, sign, code))
            result = receive(stream)
        except (OSError, UnicodeError):
            result = ""
        if result in ("OK", "NO", "ERROR"):
            emit(result)
            return 0 if result == "OK" else 1
        emit("FAILED", "the Deck did not answer")
        return 1


def main(argv):
    try:
        if len(argv) == 3 and argv[0] == "listen":
            return listen(int(argv[1]), int(argv[2]))
        if len(argv) >= 4 and argv[0] == "scan":
            return scan(int(argv[1]), int(argv[2]), argv[3:])
        if len(argv) == 3 and argv[0] == "send":
            return pair(argv[1], int(argv[2]), os.environ.get("MSW_PAIR_CODE", ""))
    except ValueError as error:
        print(error, file=sys.stderr)
    print(__doc__.strip(), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
