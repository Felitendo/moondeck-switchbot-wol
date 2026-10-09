#!/usr/bin/env python3
"""Knocks on the PC until it boots, then asks it to log in once.

    knock.py PORT TIMEOUT ADDRESS...

The secret comes from MSW_TRIGGER_SECRET, so it stays out of the process list.
Every address is tried in turn, round after round, until one answers or
TIMEOUT seconds are up. What happens is printed one line at a time, for the
log.

The other end is login-agent on the PC. The secret never goes over the wire:

    agent:  MSW-LOGIN 1 <nonce>
    knock:  base64(hmac_sha256(secret, nonce))
    agent:  OK | ALREADY-LOGGED-IN | DENIED | ERROR

Exit codes: 0 the PC logs in or already is, 1 it said no or never answered.
"""

import base64
import hashlib
import hmac
import os
import socket
import sys
import time

GREETING = "MSW-LOGIN 1 "
PAUSE = 3


def ask(address, port, secret):
    """The agent's answer, or None while nothing answers on that address."""
    try:
        with socket.create_connection((address, port), timeout=3) as connection:
            connection.settimeout(15)
            stream = connection.makefile("rw", encoding="ascii", newline="\n")
            greeting = stream.readline().strip()
            if not greeting.startswith(GREETING):
                return None
            nonce = greeting[len(GREETING):]
            digest = hmac.new(secret, nonce.encode("ascii"), hashlib.sha256).digest()
            stream.write(base64.b64encode(digest).decode("ascii") + "\n")
            stream.flush()
            return stream.readline().strip() or None
    except (OSError, UnicodeError):
        return None


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 1
    port, timeout, addresses = int(argv[0]), int(argv[1]), argv[2:]
    secret = os.environ.get("MSW_TRIGGER_SECRET", "").encode("ascii")

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for address in addresses:
            answer = ask(address, port, secret)
            if answer is None:
                continue
            if answer == "OK":
                print("%s logs in now" % address)
                return 0
            if answer == "ALREADY-LOGGED-IN":
                print("%s is already logged in" % address)
                return 0
            if answer == "DENIED":
                print("%s does not know this Deck, pair it again" % address)
            else:
                print("%s answered: %s" % (address, answer))
            return 1
        time.sleep(PAUSE)

    print("no answer from %s within %ss" % (", ".join(addresses), timeout))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
