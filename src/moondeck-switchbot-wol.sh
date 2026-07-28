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
arguments automatically; they are ignored except for logging and, when the
one-shot login trigger is configured, for finding the host on the network.

  --test              ignore the cooldown, used by the installer
  --arm-login HOST    only wait for the host and send the login trigger
  --help              show this text

Configuration: see the CONFIG_FILE path reported by --help-config.
EOF
}

SELF=$0
test_mode=0
mode=press
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
    --arm-login)
        mode=arm
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
LOGIN_TRIGGER_SECRET=${LOGIN_TRIGGER_SECRET:-}
LOGIN_TRIGGER_PORT=${LOGIN_TRIGGER_PORT:-58471}
LOGIN_TRIGGER_HOST=${LOGIN_TRIGGER_HOST:-}
LOGIN_TRIGGER_TIMEOUT=${LOGIN_TRIGGER_TIMEOUT:-240}

# Challenge and response against the agent on the host. The secret is handed
# over in the environment, never in the argument list, so it stays out of the
# process list. Runs in its own bash so a hanging connection can be killed.
trigger_login() {
    local host=$1 port=$2
    local greeting challenge response answer

    exec 3<>"/dev/tcp/$host/$port" || return 1
    if ! read -r -t 10 greeting <&3; then
        exec 3<&-
        return 1
    fi
    case $greeting in
        "MOONDECK-LOGIN-1 "*) challenge=${greeting##* } ;;
        *)
            exec 3<&-
            return 1
            ;;
    esac

    response=$(printf '%s' "$challenge" |
        openssl dgst -sha256 -hmac "$MOONDECK_LOGIN_SECRET" -binary | base64)
    printf '%s\n' "$response" >&3
    read -r -t 60 answer <&3 || answer="no answer"
    exec 3<&-

    printf '%s' "$answer"
    [[ $answer == OK || $answer == ALREADY-LOGGED-IN ]]
}
export -f trigger_login

# The host needs to boot first, so keep knocking until it answers.
arm_login() {
    local host=$1 deadline answer
    [[ -n $host ]] || die "no host address for the login trigger"
    deadline=$(($(date +%s) + LOGIN_TRIGGER_TIMEOUT))
    log "waiting for $host:$LOGIN_TRIGGER_PORT to take the login trigger"

    while (($(date +%s) < deadline)); do
        if answer=$(MOONDECK_LOGIN_SECRET="$LOGIN_TRIGGER_SECRET" \
            timeout 30 bash -c 'trigger_login "$0" "$1"' "$host" "$LOGIN_TRIGGER_PORT"); then
            log "host answered: $answer"
            return 0
        fi
        [[ -n ${answer:-} ]] && log "host answered: $answer"
        sleep 5
    done

    log "the host never took the login trigger within ${LOGIN_TRIGGER_TIMEOUT}s"
    return 1
}

if [[ $mode == arm ]]; then
    [[ -n $LOGIN_TRIGGER_SECRET ]] || die "no LOGIN_TRIGGER_SECRET in $CONFIG_FILE"
    arm_login "${1:-}"
    exit $?
fi

host_argument=${2:-${1:-}}
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

# The host is only starting to boot now, so the login trigger has to keep
# trying in the background. Its output must not stay attached to MoonDeck,
# which reads this process' stdout until it closes.
if [[ -n $LOGIN_TRIGGER_SECRET ]]; then
    trigger_host=${LOGIN_TRIGGER_HOST:-$host_argument}
    if [[ -z $trigger_host ]]; then
        log "no host address available, skipping the login trigger"
    elif command -v setsid >/dev/null 2>&1; then
        setsid "$SELF" --arm-login "$trigger_host" >/dev/null 2>>"$LOG_FILE" </dev/null &
        log "login trigger for $trigger_host handed off to the background"
    else
        ("$SELF" --arm-login "$trigger_host" >/dev/null 2>>"$LOG_FILE" </dev/null &)
        log "login trigger for $trigger_host handed off to the background"
    fi
fi
