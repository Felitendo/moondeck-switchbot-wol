"""Tests for the Python parts: the SwitchBot client, the MoonDeck settings
editor, both ends of the login trigger, and pairing. Nothing here touches the
real system: every path is in a temporary folder and the agent runs dry."""

import base64
import hashlib
import hmac
import http.server
import importlib.util
import json
import os
import queue
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "src", "lib")
AGENT = os.path.join(ROOT, "src", "login-agent")
PAIR = os.path.join(LIB, "pair.py")
FIXTURE = os.path.join(ROOT, "tests", "moondeck-settings.json")

TOKEN = "a" * 96
SECRET = "b" * 32
TRIGGER = "0123456789abcdef0123456789abcdef"


class SwitchBotMock(http.server.BaseHTTPRequestHandler):
    """Answers like the real API, and checks the signature like it."""

    commands = []

    def signed(self):
        expected = base64.b64encode(hmac.new(
            SECRET.encode(),
            (TOKEN + self.headers["t"] + self.headers["nonce"]).encode(),
            hashlib.sha256).digest()).decode()
        return self.headers["Authorization"] == TOKEN and self.headers["sign"] == expected

    def answer(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self.signed():
            self.answer(401, {"message": "Unauthorized"})
        else:
            self.answer(200, {"statusCode": 100, "message": "success", "body": {"deviceList": [
                {"deviceId": "C0FFEE000002", "deviceName": "Lamp", "deviceType": "Plug Mini (EU)"},
                {"deviceId": "C0FFEE000001", "deviceName": "PC Power", "deviceType": "Bot"},
            ]}})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length))
        if not self.signed():
            self.answer(401, {"message": "Unauthorized"})
        elif "C0FFEE000001" not in self.path:
            self.answer(200, {"statusCode": 152, "message": "device not found"})
        else:
            SwitchBotMock.commands.append(body["command"])
            self.answer(200, {"statusCode": 100, "message": "success", "body": {}})

    def log_message(self, *_):
        pass


def start_mock():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), SwitchBotMock)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


class SwitchBotTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = start_mock()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def run_helper(self, *args, token=TOKEN):
        env = dict(os.environ, MSW_SB_TOKEN=token, MSW_SB_SECRET=SECRET,
                   MSW_SB_API="http://127.0.0.1:%d/v1.1" % self.server.server_port)
        return subprocess.run([sys.executable, os.path.join(LIB, "switchbot.py"), *args],
                              env=env, capture_output=True, text=True, check=False)

    def test_devices_put_bots_first(self):
        result = self.run_helper("devices")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.splitlines()[0], "C0FFEE000001\tPC Power\tBot")

    def test_command(self):
        result = self.run_helper("command", "C0FFEE000001", "press")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(SwitchBotMock.commands[-1], "press")

    def test_wrong_token(self):
        result = self.run_helper("devices", token="c" * 96)
        self.assertEqual(result.returncode, 3)
        self.assertIn("Unauthorized", result.stdout)

    def test_api_error(self):
        result = self.run_helper("command", "NOPE", "press")
        self.assertEqual((result.returncode, result.stdout.strip()), (3, "152\tdevice not found"))

    def test_unreachable(self):
        env = dict(os.environ, MSW_SB_API="http://127.0.0.1:9/v1.1")
        result = subprocess.run([sys.executable, os.path.join(LIB, "switchbot.py"), "devices"],
                                env=env, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 2)


class MoonDeckTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, "settings.json")
        shutil.copy(FIXTURE, self.path)
        with open(FIXTURE, encoding="utf-8") as handle:
            self.original = json.load(handle)
        self.host = self.original["currentHostId"]

    def tearDown(self):
        shutil.rmtree(self.dir)

    def helper(self, *args):
        result = subprocess.run([sys.executable, os.path.join(LIB, "moondeck.py"), self.path, *args],
                                capture_output=True, text=True, check=True)
        return result.stdout

    def load(self):
        with open(self.path, encoding="utf-8") as handle:
            return json.load(handle)["hostSettings"][self.host]

    def test_hosts(self):
        self.assertEqual(self.helper("hosts").rstrip("\n").split("\x1f"),
                         [self.host, "gaming-pc", "192.168.2.50", "1", "0", ""])

    def test_point_and_restore(self):
        change = self.helper("point", self.host, "/x/wake", "180")
        host = self.load()
        self.assertEqual(host["wolSettings"], {"useCustomWolExec": True, "sendOnce": True,
                                               "customWolExecPath": "/x/wake", "port": 9})
        self.assertEqual(host["runnerTimeouts"]["wakeOnLan"], 180)

        self.helper("restore", change.strip())
        with open(self.path, encoding="utf-8") as handle:
            self.assertEqual(json.load(handle), self.original)

    def test_restore_keeps_what_the_user_changed_since(self):
        change = self.helper("point", self.host, "/x/wake", "180")
        with open(self.path, encoding="utf-8") as handle:
            data = json.load(handle)
        data["hostSettings"][self.host]["runnerTimeouts"]["wakeOnLan"] = 300
        with open(self.path, "w", encoding="utf-8") as handle:
            json.dump(data, handle)

        self.helper("restore", change.strip())
        host = self.load()
        self.assertEqual(host["runnerTimeouts"]["wakeOnLan"], 300)
        self.assertFalse(host["wolSettings"]["useCustomWolExec"])

    def test_a_longer_timeout_stays(self):
        self.helper("point", self.host, "/x/wake", "30")
        self.assertEqual(self.load()["runnerTimeouts"]["wakeOnLan"], 60)


class AgentTest(unittest.TestCase):
    """The agent on its own, then together with knock.py."""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.conf = os.path.join(self.dir, "etc")
        self.dm = os.path.join(self.dir, "plasmalogin.conf")
        os.makedirs(self.conf)
        with open(os.path.join(self.conf, "host.conf"), "w", encoding="utf-8") as handle:
            handle.write("# test\nEnabled=yes\nUser=alice\nPort=58471\n")
        with open(os.path.join(self.conf, "secret"), "w", encoding="utf-8") as handle:
            handle.write(TRIGGER + "\n")
        self.env = dict(os.environ, MSW_HOST_CONFDIR=self.conf,
                        MSW_HOST_STATEDIR=os.path.join(self.dir, "var"),
                        MSW_DM_CONFIG=self.dm, MSW_DRY_RUN="1")

    def tearDown(self):
        shutil.rmtree(self.dir)

    def agent(self, *args, **kwargs):
        return subprocess.run([sys.executable, AGENT, *args], env=self.env,
                              capture_output=True, text=True, check=False, **kwargs)

    def write_dm(self, text):
        with open(self.dm, "w", encoding="utf-8") as handle:
            handle.write(text)

    def read_dm(self):
        with open(self.dm, encoding="utf-8") as handle:
            return handle.read()

    def arm(self):
        # The agent's own functions, with the test's paths.
        code = ("import importlib.machinery, importlib.util, sys; "
                "loader = importlib.machinery.SourceFileLoader('agent', sys.argv[1]); "
                "agent = importlib.util.module_from_spec(importlib.util.spec_from_loader('agent', loader)); "
                "loader.exec_module(agent); "
                "agent.arm(sys.argv[2], 'alice')")
        subprocess.run([sys.executable, "-c", code, AGENT, self.dm], env=self.env, check=True,
                       capture_output=True)

    def round_trip(self, before):
        if before is not None:
            self.write_dm(before)
        self.arm()
        armed = self.read_dm()
        self.assertIn("User=alice", armed)
        self.agent("--disarm")
        if before is None:
            self.assertFalse(os.path.exists(self.dm))
        else:
            self.assertEqual(self.read_dm(), before)
        return armed

    def test_section_with_session(self):
        armed = self.round_trip("[Autologin]\nSession=plasma\n")
        self.assertEqual(armed, "[Autologin]\nUser=alice\nSession=plasma\n")

    def test_user_already_set(self):
        self.round_trip("[General]\nNumlock=on\n\n[Autologin]\nUser=bob\n")

    def test_no_section(self):
        self.round_trip("[General]\nNumlock=on\n")

    def test_no_file(self):
        self.round_trip(None)

    def test_check(self):
        result = self.agent("--check")
        self.assertEqual((result.returncode, result.stdout.strip()), (0, self.dm))

    def serve(self):
        """Starts the agent for every connection, the way the socket unit does."""
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen()

        def accept():
            while True:
                try:
                    connection, _ = listener.accept()
                except OSError:
                    return
                with connection:
                    subprocess.run([sys.executable, AGENT], env=self.env, stdin=connection,
                                   stdout=connection, stderr=subprocess.DEVNULL, check=False)

        threading.Thread(target=accept, daemon=True).start()
        self.addCleanup(listener.close)
        return listener.getsockname()[1]

    def knock(self, port, secret):
        env = dict(os.environ, MSW_TRIGGER_SECRET=secret)
        # The first address answers nothing, the second is the agent.
        return subprocess.run([sys.executable, os.path.join(LIB, "knock.py"), str(port), "20",
                               "127.0.0.2", "127.0.0.1"], env=env, capture_output=True,
                              text=True, check=False, timeout=60)

    def test_knock_logs_in_once(self):
        self.write_dm("[Autologin]\nSession=plasma\n")
        port = self.serve()
        result = self.knock(port, TRIGGER)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("127.0.0.1 logs in now", result.stdout)
        # Armed, logged in (dry run) and taken back out again.
        self.assertEqual(self.read_dm(), "[Autologin]\nSession=plasma\n")
        with open(os.path.join(self.dir, "var", "last"), encoding="utf-8") as handle:
            self.assertTrue(handle.read().endswith("\tlogin\n"))

    def test_knock_with_the_wrong_secret(self):
        self.write_dm("[Autologin]\nSession=plasma\n")
        port = self.serve()
        result = self.knock(port, "f" * 32)
        self.assertEqual(result.returncode, 1)
        self.assertIn("does not know this Deck", result.stdout)
        self.assertEqual(self.read_dm(), "[Autologin]\nSession=plasma\n")


def load_pair():
    spec = importlib.util.spec_from_file_location("pair", PAIR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


class Pairing:
    """pair.py in the background, line by line."""

    def __init__(self, test, *args, code=""):
        self.process = subprocess.Popen(
            [sys.executable, PAIR, *map(str, args)], env=dict(os.environ, MSW_PAIR_CODE=code),
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        self.lines = queue.Queue()
        threading.Thread(target=self.read, daemon=True).start()
        test.addCleanup(self.stop)

    def read(self):
        for line in self.process.stdout:
            self.lines.put(line.split())
        self.lines.put(["END"])

    def next(self):
        return self.lines.get(timeout=30)

    def say(self, answer):
        self.process.stdin.write(answer + "\n")
        self.process.stdin.flush()

    def stop(self):
        self.process.kill()
        self.process.wait()
        self.process.stdin.close()
        self.process.stdout.close()


class PairTest(unittest.TestCase):
    CODE = "msw1:" + base64.b64encode(("TriggerSecret=%s\n" % TRIGGER).encode()).decode()

    def deck(self):
        """A Deck that waits, once a scan finds it."""
        port = free_port()
        deck = Pairing(self, "listen", port, 30)
        scan = subprocess.run([sys.executable, PAIR, "scan", str(port), "20", "127.0.0.1"],
                              capture_output=True, text=True, check=False, timeout=60)
        self.assertEqual(scan.stdout.split()[:2], ["FOUND", "127.0.0.1"])
        return deck, port

    def meet(self):
        """A Deck and a PC that both show the same digits."""
        deck, port = self.deck()
        pc = Pairing(self, "send", "127.0.0.1", port, code=self.CODE)
        pc_peer, deck_peer = pc.next(), deck.next()
        self.assertEqual(pc_peer[0], "PEER")
        self.assertEqual(deck_peer[:3], ["PEER", pc_peer[1], "127.0.0.1"])
        return deck, pc

    def test_pairing(self):
        deck, pc = self.meet()
        deck.say("yes")
        pc.say("yes")
        self.assertEqual(deck.next(), ["DATA", self.CODE])
        deck.say("ok")
        self.assertEqual(deck.next(), ["DONE"])
        self.assertEqual(pc.next(), ["OK"])

    def test_the_deck_says_no(self):
        deck, pc = self.meet()
        deck.say("no")
        pc.say("yes")
        self.assertEqual(pc.next(), ["NO"])

    def test_the_pc_says_no(self):
        deck, pc = self.meet()
        deck.say("yes")
        pc.say("no")
        self.assertEqual(deck.next(), ["CANCELLED"])

    def test_a_key_other_than_the_one_committed_to(self):
        pair = load_pair()
        deck, port = self.deck()
        _, committed = pair.keypair()
        _, sent = pair.keypair()
        with socket.create_connection(("127.0.0.1", port), timeout=10) as connection:
            stream = connection.makefile("rw", encoding="ascii", newline="\n")
            stream.readline()
            pair.send(stream, "COMMIT %s mallory" % pair.commitment(committed))
            stream.readline()
            pair.send(stream, "KEY %x" % sent)
            self.assertEqual(stream.readline(), "")
        # Turned away without asking, and still waiting for the real PC.
        pc = Pairing(self, "send", "127.0.0.1", port, code=self.CODE)
        self.assertEqual(deck.next()[0], "PEER")
        self.assertEqual(pc.next()[0], "PEER")

    def test_changed_on_the_way(self):
        pair = load_pair()
        encrypt, sign, _ = pair.derive(5, 7, 11, 13)
        sealed = pair.seal(encrypt, sign, self.CODE)
        self.assertEqual(pair.unseal(encrypt, sign, sealed), self.CODE)
        data, tag = sealed.split(" ")
        changed = base64.b64encode(bytes([base64.b64decode(data)[0] ^ 1]) + base64.b64decode(data)[1:])
        self.assertIsNone(pair.unseal(encrypt, sign, "%s %s" % (changed.decode(), tag)))

    def test_the_prime(self):
        pair = load_pair()
        # A typo in it would not survive these.
        self.assertEqual(pow(2, pair.P - 1, pair.P), 1)
        self.assertEqual(pow(2, (pair.P - 1) // 2 - 1, (pair.P - 1) // 2), 1)

    def test_targets(self):
        pair = load_pair()
        home = pair.targets(["192.168.2.10/24"])
        self.assertEqual((len(home), home[0], home[-1]), (254, "192.168.2.1", "192.168.2.254"))
        big = pair.targets(["10.1.2.3/8"])
        self.assertEqual((len(big), big[0]), (254, "10.1.2.1"))
        self.assertEqual(pair.targets(["127.0.0.1"]), ["127.0.0.1"])


if __name__ == "__main__":
    unittest.main()
