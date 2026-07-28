#!/usr/bin/env bash
#
# Guided setup for the MoonDeck SwitchBot wake-up script.

set -euo pipefail

RAW_BASE=${MOONDECK_RAW_BASE:-https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main}
BOOTSTRAP_DIR=${MOONDECK_BOOTSTRAP_DIR:-}
trap 'if [[ -n $BOOTSTRAP_DIR ]]; then rm -rf "$BOOTSTRAP_DIR"; fi' EXIT

# Fetch the pieces this script needs when it was run on its own, without the
# rest of the repository next to it.
bootstrap() {
    command -v curl >/dev/null 2>&1 || {
        printf 'curl is required to download the missing parts\n' >&2
        exit 1
    }
    BOOTSTRAP_DIR=$(mktemp -d)
    local part
    for part in "$@"; do
        mkdir -p "$BOOTSTRAP_DIR/$(dirname "$part")"
        curl -fsSL "$RAW_BASE/$part" -o "$BOOTSTRAP_DIR/$part" || {
            printf 'could not download %s\n' "$part" >&2
            exit 1
        }
    done
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || SCRIPT_DIR=""
if [[ -r ${SCRIPT_DIR:-}/lib/i18n.sh ]]; then
    ROOT_DIR=$SCRIPT_DIR
else
    bootstrap lib/i18n.sh lib/ui.sh lib/switchbot.sh src/moondeck-switchbot-wol.sh
    ROOT_DIR=$BOOTSTRAP_DIR
fi

# shellcheck source=lib/i18n.sh
source "$ROOT_DIR/lib/i18n.sh"

for arg in "$@"; do
    case $arg in
        --cli) MSB_FORCE_CLI=1 ;;
        --help | -h)
            t usage
            exit 0
            ;;
        *)
            t usage >&2
            exit 1
            ;;
    esac
done

# shellcheck source=lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=lib/switchbot.sh
source "$ROOT_DIR/lib/switchbot.sh"

TITLE=$(t app_title)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/moondeck-switchbot"
CONFIG_FILE="$CONFIG_DIR/config"
DEFAULT_TARGET="$HOME/moondeck-switchbot-wol.sh"
SOURCE_SCRIPT="$ROOT_DIR/src/moondeck-switchbot-wol.sh"

fail() {
    ui_error "$TITLE" "$1"
    exit 1
}

abort() {
    printf '%s\n' "$(t cancelled)" >&2
    exit 1
}

for dependency in curl openssl python3; do
    command -v "$dependency" >/dev/null 2>&1 || fail "$(t dep_missing "$dependency")"
done
[[ -r $SOURCE_SCRIPT ]] || fail "$(t write_failed "$SOURCE_SCRIPT")"

ui_info "$TITLE" "$(t welcome)"
ui_info "$TITLE" "$(t creds_intro "$CONFIG_FILE")"

while true; do
    token=$(ui_password "$TITLE" "$(t ask_token)") || abort
    [[ -n $token ]] || fail "$(t input_empty)"
    secret=$(ui_password "$TITLE" "$(t ask_secret)") || abort
    [[ -n $secret ]] || fail "$(t input_empty)"

    response_file=$(mktemp)
    if ! ui_progress_run "$(t fetching)" "$response_file" sb_curl "$token" "$secret" "/devices"; then
        rm -f "$response_file"
        ui_error "$TITLE" "$(t api_unreachable)"
        continue
    fi
    response=$(cat "$response_file")
    rm -f "$response_file"

    mapfile -t lines < <(printf '%s' "$response" | sb_parse_devices)
    if [[ ${lines[0]:-} == ERR* ]]; then
        IFS=$'\t' read -r _ status_code message <<<"${lines[0]}"
        ui_error "$TITLE" "$(t api_error "$status_code" "$message")"
        continue
    fi

    devices=("${lines[@]:1}")
    ((${#devices[@]} > 0)) || fail "$(t no_devices)"
    break
done

choices=()
for line in "${devices[@]}"; do
    IFS=$'\t' read -r device_id device_name device_type <<<"$line"
    choices+=("$device_id" "$device_name ($device_type)")
done

selected_device=$(ui_choose "$TITLE" "$(t choose_device)" "${choices[@]}") || abort
[[ -n $selected_device ]] || abort

selected_command=$(ui_choose "$TITLE" "$(t ask_mode)" \
    press "$(t mode_press)" \
    turnOn "$(t mode_switch)") || abort
[[ -n $selected_command ]] || abort

target=$(ui_input "$TITLE" "$(t ask_path)" "$DEFAULT_TARGET") || abort
[[ -n $target ]] || abort
target=${target/#\~/$HOME}

if [[ -e $target ]]; then
    ui_yesno "$TITLE" "$(t path_exists "$target")" || abort
fi

trigger_secret=""
trigger_port=""
trigger_host=""
if ui_yesno "$TITLE" "$(t trigger_ask)"; then
    trigger_secret=$(ui_password "$TITLE" "$(t trigger_secret)") || abort
    [[ -n $trigger_secret ]] || fail "$(t input_empty)"
    trigger_port=$(ui_input "$TITLE" "$(t trigger_port)" "58471") || abort
    trigger_host=$(ui_input "$TITLE" "$(t trigger_host)" "") || abort
fi

install -D -m 600 /dev/null "$CONFIG_FILE" 2>/dev/null || fail "$(t write_failed "$CONFIG_FILE")"
chmod 700 "$CONFIG_DIR"
{
    printf '# moondeck-switchbot-wol configuration\n'
    printf '# Written by install.sh - this file holds API credentials, keep it private.\n'
    printf 'TOKEN=%q\n' "$token"
    printf 'SECRET=%q\n' "$secret"
    printf 'DEVICE_ID=%q\n' "$selected_device"
    printf 'COMMAND=%q\n' "$selected_command"
    printf '# Seconds in which no second button press is sent, 0 disables the cooldown.\n'
    printf 'COOLDOWN=180\n'
    printf '# Where install.sh put the script, used by uninstall.sh.\n'
    printf 'INSTALL_PATH=%q\n' "$target"
    if [[ -n $trigger_secret ]]; then
        printf '# One-shot login trigger, see host/install-host.sh on the host.\n'
        printf 'LOGIN_TRIGGER_SECRET=%q\n' "$trigger_secret"
        printf 'LOGIN_TRIGGER_PORT=%q\n' "${trigger_port:-58471}"
        printf 'LOGIN_TRIGGER_HOST=%q\n' "$trigger_host"
        printf '# Seconds to keep knocking while the host boots.\n'
        printf 'LOGIN_TRIGGER_TIMEOUT=240\n'
    fi
} >"$CONFIG_FILE"

mkdir -p "$(dirname "$target")"
sed "s|@CONFIG_PATH@|$CONFIG_FILE|" "$SOURCE_SCRIPT" >"$target" || fail "$(t write_failed "$target")"
chmod 755 "$target"

# The script logs to stdout and curl complains on stderr, the dialog should
# show both.
run_wake_test() {
    "$target" --test 2>&1
}

if ui_yesno "$TITLE" "$(t test_ask)"; then
    test_output=$(mktemp)
    if ui_progress_run "$(t testing)" "$test_output" run_wake_test; then
        ui_info "$TITLE" "$(t test_ok)"
    else
        ui_error "$TITLE" "$(t test_failed "$(cat "$test_output")")"
    fi
    rm -f "$test_output"
fi

ui_info "$TITLE" "$(t done "$target")"
