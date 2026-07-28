#!/usr/bin/env bash
#
# The little bit of SwitchBot API v1.1 the installer needs. The installed
# wake-up script carries its own copy of this so it stays a single, standalone
# file - keep both in sync when the API changes.

MSB_API_BASE=${MSB_API_BASE:-https://api.switch-bot.com/v1.1}

sb_nonce() {
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        openssl rand -hex 16
    fi
}

# sb_curl <token> <secret> <path> [extra curl arguments...]
sb_curl() {
    local token=$1 secret=$2 path=$3
    shift 3
    local nonce timestamp signature
    nonce=$(sb_nonce)
    timestamp=$(date +%s%3N)
    signature=$(printf '%s%s%s' "$token" "$timestamp" "$nonce" |
        openssl dgst -sha256 -hmac "$secret" -binary | base64)

    curl -sS --max-time 20 "$MSB_API_BASE$path" \
        -H "Authorization: $token" \
        -H "sign: $signature" \
        -H "nonce: $nonce" \
        -H "t: $timestamp" \
        -H "Content-Type: application/json; charset=utf-8" \
        "$@"
}

# Turns the device list JSON on stdin into tab separated lines. The first line
# is either "OK" or "ERR<TAB>statusCode<TAB>message", every following line is
# "deviceId<TAB>deviceName<TAB>deviceType". Bots are listed first.
sb_parse_devices() {
    python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except ValueError:
    print("ERR\t-\tthe API did not return valid JSON")
    sys.exit(0)

if data.get("statusCode") != 100:
    print("ERR\t%s\t%s" % (data.get("statusCode", "-"), data.get("message", "")))
    sys.exit(0)

devices = data.get("body", {}).get("deviceList", []) or []
devices.sort(key=lambda d: (d.get("deviceType", "") != "Bot", d.get("deviceName", "")))

print("OK")
for device in devices:
    print("%s\t%s\t%s" % (device.get("deviceId", ""),
                          device.get("deviceName", "?"),
                          device.get("deviceType", "?")))
'
}
