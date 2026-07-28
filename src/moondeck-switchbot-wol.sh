#!/usr/bin/env bash
#
# moondeck-switchbot-wol
#
# Drop-in replacement for MoonDeck's Wake-on-LAN magic packet. Instead of
# putting a packet on the wire, it asks the SwitchBot cloud to push the
# physical power button of the host PC.
#
# MoonDeck invokes this executable as:
#   moondeck-switchbot-wol <HOSTNAME> <IP_ADDRESS> <PORT> <MAC>
# None of those arguments are needed here, they are only written to the log.
#
# A non-zero exit code is reported back to MoonDeck as a failed wake-up.

set -euo pipefail

# The installer replaces the placeholder below with an absolute path, so the
# script does not depend on $HOME being set the way we expect (Decky plugin
# backends do not necessarily run as the desktop user).
CONFIG_DEFAULT='@CONFIG_PATH@'
case $CONFIG_DEFAULT in
    '@'CONFIG_PATH'@') CONFIG_DEFAULT="${XDG_CONFIG_HOME:-$HOME/.config}/moondeck-switchbot/config" ;;
esac
CONFIG_FILE=${MOONDECK_SWITCHBOT_CONFIG:-$CONFIG_DEFAULT}

STATE_PREFIX="/tmp/moondeck-switchbot-$(id -u)"
STAMP_FILE="$STATE_PREFIX.stamp"
LOG_FILE="$STATE_PREFIX.log"

log() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') $*"
    printf '%s\n' "$line"
    printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || true
}

die() {
    log "ERROR: $*"
    exit 1
}

usage() {
    cat <<'EOF'
Usage: moondeck-switchbot-wol [--test] [HOSTNAME IP_ADDRESS PORT MAC]

Triggers the configured SwitchBot device. MoonDeck passes the four host
arguments automatically; they are ignored except for logging.

  --test   ignore the cooldown, used by the installer to verify the setup
  --help   show this text

Configuration: see the CONFIG_FILE path reported by --help-config.
EOF
}

test_mode=0
case ${1:-} in
    --help | -h)
        usage
        exit 0
        ;;
    --help-config)
        printf '%s\n' "$CONFIG_FILE"
        exit 0
        ;;
    --test)
        test_mode=1
        shift
        ;;
esac

[[ -r $CONFIG_FILE ]] || die "config file not readable: $CONFIG_FILE (run install.sh first)"
# shellcheck source=/dev/null
source "$CONFIG_FILE"

for required in TOKEN SECRET DEVICE_ID; do
    [[ -n ${!required:-} ]] || die "$required is missing in $CONFIG_FILE"
done
COMMAND=${COMMAND:-press}
COOLDOWN=${COOLDOWN:-180}
API_BASE=${API_BASE:-https://api.switch-bot.com/v1.1}

log "invoked with: ${*:-<no arguments>}"

now=$(date +%s)
last=0
if [[ -r $STAMP_FILE ]]; then
    read -r last <"$STAMP_FILE" || last=0
fi
[[ $last =~ ^[0-9]+$ ]] || last=0

# Pressing a power button twice is not as harmless as sending a second magic
# packet, so refuse to press again while the host is most likely still booting.
if ((test_mode == 0 && COOLDOWN > 0 && now - last < COOLDOWN)); then
    log "cooldown active, $((COOLDOWN - (now - last)))s left - not pressing again"
    exit 0
fi

nonce() {
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        openssl rand -hex 16
    fi
}

request_nonce=$(nonce)
timestamp=$(date +%s%3N)
signature=$(printf '%s%s%s' "$TOKEN" "$timestamp" "$request_nonce" |
    openssl dgst -sha256 -hmac "$SECRET" -binary | base64)

response=$(curl -sS --max-time 20 -X POST \
    "$API_BASE/devices/$DEVICE_ID/commands" \
    -H "Authorization: $TOKEN" \
    -H "sign: $signature" \
    -H "nonce: $request_nonce" \
    -H "t: $timestamp" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "{\"command\":\"$COMMAND\",\"parameter\":\"default\",\"commandType\":\"command\"}") ||
    die "the request to the SwitchBot API failed"

log "API response: $response"

# Match against a whitespace free copy so the check does not depend on how the
# API happens to format its JSON.
compact_response=${response//[[:space:]]/}
[[ $compact_response == *'"statusCode":100'* ]] ||
    die "the SwitchBot API rejected the command: $response"

printf '%s\n' "$now" >"$STAMP_FILE" 2>/dev/null || true
log "SwitchBot command '$COMMAND' sent successfully"
