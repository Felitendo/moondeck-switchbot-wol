#!/usr/bin/env python3
"""Reads and changes the per-host WOL settings in MoonDeck's settings.json.

    moondeck.py FILE hosts
        One line per host: id, name, address, whether it is the current
        host (1/0), whether it runs a custom WOL executable (1/0), its path.
        The fields are split by the unit separator (0x1f) rather than tabs,
        so an empty one cannot make the shell skip it.
    moondeck.py FILE point ID PATH TIMEOUT
        Makes host ID run PATH instead of sending a magic packet, send it only
        once, and wait at least TIMEOUT seconds for the host. Prints what it
        changed as one JSON line, for `restore`.
    moondeck.py FILE restore JSON
        Puts back what `point` changed. A value the user has changed since is
        left alone.

MoonDeck's frontend reads this file when Steam starts in Game Mode and writes
all of it back on every change. So a change made here holds when it is made
from Desktop Mode, which is where this runs.
"""

import json
import os
import sys
import tempfile

# Where each setting lives inside a host's entry.
KEYS = {
    "useCustomWolExec": ("wolSettings", "useCustomWolExec"),
    "customWolExecPath": ("wolSettings", "customWolExecPath"),
    "sendOnce": ("wolSettings", "sendOnce"),
    "wakeOnLan": ("runnerTimeouts", "wakeOnLan"),
}


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def save(path, data):
    # Written the way MoonDeck writes it, through a temporary file so a crash
    # cannot leave half a settings file behind.
    folder = os.path.dirname(path) or "."
    descriptor, temporary = tempfile.mkstemp(dir=folder, prefix=".settings.")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, allow_nan=False, indent=4)
        os.chmod(temporary, os.stat(path).st_mode & 0o777)
        os.replace(temporary, path)
    except BaseException:
        os.unlink(temporary)
        raise


def get(host, key):
    section, name = KEYS[key]
    return host.get(section, {}).get(name)


def put(host, key, value):
    section, name = KEYS[key]
    host.setdefault(section, {})[name] = value


def host_of(data, host_id):
    host = (data.get("hostSettings") or {}).get(host_id)
    if host is None:
        sys.exit("no host %s in MoonDeck's settings" % host_id)
    return host


def hosts(data):
    current = data.get("currentHostId")
    for host_id, host in (data.get("hostSettings") or {}).items():
        print("\x1f".join([
            host_id,
            host.get("hostName", ""),
            host.get("address", ""),
            "1" if host_id == current else "0",
            "1" if get(host, "useCustomWolExec") else "0",
            get(host, "customWolExecPath") or "",
        ]))


def point(path, data, host_id, executable, timeout):
    host = host_of(data, host_id)
    wanted = {
        "useCustomWolExec": True,
        "customWolExecPath": executable,
        # A second press switches the PC off again.
        "sendOnce": True,
        # A cold boot takes far longer than waking from sleep.
        "wakeOnLan": max(int(get(host, "wakeOnLan") or 0), int(timeout)),
    }
    before = {key: get(host, key) for key in wanted}
    for key, value in wanted.items():
        put(host, key, value)
    save(path, data)
    print(json.dumps({"id": host_id, "before": before, "after": wanted}))


def restore(path, data, change):
    host = (data.get("hostSettings") or {}).get(change["id"])
    if host is None:
        return  # removed from MoonDeck since, nothing to put back
    for key, value in change["before"].items():
        # MoonDeck checks the types of its settings, so a value that was not
        # there before is not put back as null.
        if value is not None and get(host, key) == change["after"].get(key):
            put(host, key, value)
    save(path, data)


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 1
    path, command, args = argv[0], argv[1], argv[2:]
    try:
        data = load(path)
    except FileNotFoundError:
        return 4  # no MoonDeck
    if command == "hosts" and not args:
        hosts(data)
    elif command == "point" and len(args) == 3:
        point(path, data, *args)
    elif command == "restore" and len(args) == 1:
        restore(path, data, json.loads(args[0]))
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
