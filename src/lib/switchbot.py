#!/usr/bin/env python3
"""The little bit of the SwitchBot API v1.1 this program needs.

    switchbot.py devices             one line per device: id, name, type
    switchbot.py command ID COMMAND  send a command, e.g. press or turnOn

The credentials come from MSW_SB_TOKEN and MSW_SB_SECRET, so they never show
up in the process list.

Exit codes: 0 done, 2 the API could not be reached, 3 the API said no. On
an error the one line on stdout says why: the reason for 2, and
"statusCode<TAB>message" for 3.
"""

import base64
import hashlib
import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

API = os.environ.get("MSW_SB_API", "https://api.switch-bot.com/v1.1")


def headers(token, secret):
    # https://github.com/OpenWonderLabs/SwitchBotAPI#authentication
    stamp = str(int(time.time() * 1000))
    nonce = str(uuid.uuid4())
    digest = hmac.new(secret.encode(), (token + stamp + nonce).encode(),
                      hashlib.sha256).digest()
    return {
        "Authorization": token,
        "sign": base64.b64encode(digest).decode(),
        "nonce": nonce,
        "t": stamp,
        "Content-Type": "application/json; charset=utf-8",
    }


def call(path, body=None):
    token = os.environ.get("MSW_SB_TOKEN", "")
    secret = os.environ.get("MSW_SB_SECRET", "")
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data,
                                     headers=headers(token, secret))
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            answer = json.load(response)
    except urllib.error.HTTPError as error:
        # A wrong token is a 401 with a JSON body that says so.
        try:
            answer = json.load(error)
            answer.setdefault("statusCode", error.code)
        except ValueError:
            print("%s\t%s" % (error.code, error.reason))
            sys.exit(3)
    except (OSError, ValueError) as error:
        print(getattr(error, "reason", None) or error)
        sys.exit(2)

    if answer.get("statusCode") != 100:
        print("%s\t%s" % (answer.get("statusCode", "?"), answer.get("message", "")))
        sys.exit(3)
    return answer.get("body") or {}


def devices():
    found = call("/devices").get("deviceList") or []
    # Bots first, they are what presses a button.
    found.sort(key=lambda d: (d.get("deviceType") != "Bot", d.get("deviceName", "")))
    for device in found:
        print("%s\t%s\t%s" % (device.get("deviceId", ""),
                              device.get("deviceName", "?"),
                              device.get("deviceType", "?")))


def command(device, name):
    call("/devices/%s/commands" % device,
         {"command": name, "parameter": "default", "commandType": "command"})


def main(argv):
    if argv[:1] == ["devices"] and len(argv) == 1:
        devices()
    elif argv[:1] == ["command"] and len(argv) == 3:
        command(argv[1], argv[2])
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
