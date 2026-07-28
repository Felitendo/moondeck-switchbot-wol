#!/usr/bin/env bash
#
# Sets up the one-shot login trigger on the host PC. Run this on the machine
# that gets woken up, without sudo in front: it asks all its questions as you,
# with dialogs, and only the installation itself goes through sudo.

set -euo pipefail

RAW_BASE=${MOONDECK_RAW_BASE:-https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main}
BOOTSTRAP_DIR=${MOONDECK_BOOTSTRAP_DIR:-}
trap 'if [[ -n $BOOTSTRAP_DIR ]]; then rm -rf "$BOOTSTRAP_DIR"; fi' EXIT

SELF_PART=host/install-host.sh
# Piping into bash makes standard input the script itself, which is where the
# wizard needs to read the answers from. Fetch a real copy and hand over to it,
# with standard input back on the terminal.
if [[ $0 == bash || $0 == */bash ]]; then
    command -v curl >/dev/null 2>&1 || {
        printf 'curl is required\n' >&2
        exit 1
    }
    [[ -n $BOOTSTRAP_DIR ]] || BOOTSTRAP_DIR=$(mktemp -d)
    curl -fsSL "$RAW_BASE/$SELF_PART" -o "$BOOTSTRAP_DIR/entry.sh" || {
        printf 'could not download %s\n' "$SELF_PART" >&2
        exit 1
    }
    export MOONDECK_RAW_BASE="$RAW_BASE" MOONDECK_BOOTSTRAP_DIR="$BOOTSTRAP_DIR"
    # a readable /dev/tty node does not mean it can be opened, only trying does
    if (: </dev/tty) 2>/dev/null; then
        exec bash "$BOOTSTRAP_DIR/entry.sh" "$@" </dev/tty
    fi
    exec bash "$BOOTSTRAP_DIR/entry.sh" "$@"
fi

# Works without the repository next to it, see install.sh.
bootstrap() {
    command -v curl >/dev/null 2>&1 || {
        printf 'curl is required to download the missing parts\n' >&2
        exit 1
    }
    [[ -n $BOOTSTRAP_DIR ]] || BOOTSTRAP_DIR=$(mktemp -d)
    local part
    for part in "$@"; do
        mkdir -p "$BOOTSTRAP_DIR/$(dirname "$part")"
        curl -fsSL "$RAW_BASE/$part" -o "$BOOTSTRAP_DIR/$part" || {
            printf 'could not download %s\n' "$part" >&2
            exit 1
        }
    done
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd) || SCRIPT_DIR=""
if [[ -r ${SCRIPT_DIR:-}/../lib/i18n.sh ]]; then
    ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
else
    bootstrap lib/i18n.sh lib/ui.sh lib/switchbot.sh \
        host/install-host.sh \
        host/moondeck-login-agent \
        host/moondeck-login-agent.socket \
        host/moondeck-login-agent@.service \
        host/moondeck-login-disarm.service
    ROOT_DIR=$BOOTSTRAP_DIR
fi
HOST_DIR=$ROOT_DIR/host
SELF_PATH=$HOST_DIR/install-host.sh

# shellcheck source=../lib/i18n.sh
source "$ROOT_DIR/lib/i18n.sh"

MODE=install
for arg in "$@"; do
    case $arg in
        --cli) MSB_FORCE_CLI=1 ;;
        --uninstall | --token | --apply | --apply-uninstall) MODE=${arg#--} ;;
        *) ;;
    esac
done

# The privileged half runs under sudo and has no session to draw dialogs on.
[[ $MODE == apply* ]] && MSB_FORCE_CLI=1

# shellcheck source=../lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"
# shellcheck source=../lib/switchbot.sh
source "$ROOT_DIR/lib/switchbot.sh"

TITLE=$(t app_title)
AGENT_TARGET=/usr/local/lib/moondeck-login-agent
UNIT_DIR=/etc/systemd/system
CONFIG_DIR=/etc/moondeck-login-agent
UFW_COMMENT="moondeck login trigger"

fail() {
    ui_error "$TITLE" "$1"
    exit 1
}

abort() {
    printf '%s\n' "$(t cancelled)" >&2
    exit 1
}

# --- the privileged half -----------------------------------------------------
#
# Only ever reached through sudo. What it needs arrives in a file, so no secret
# has to travel through the argument list where the process list would show it,
# and the only thing it writes to standard output is the secret the trigger
# ended up with.

remove_everything() {
    # undo a still armed autologin before the agent itself disappears
    [[ -x $AGENT_TARGET ]] && "$AGENT_TARGET" --disarm >/dev/null 2>&1
    systemctl disable --now moondeck-login-agent.socket >/dev/null 2>&1 || true
    systemctl disable moondeck-login-disarm.service >/dev/null 2>&1 || true
    rm -f "$UNIT_DIR/moondeck-login-agent.socket" \
        "$UNIT_DIR/moondeck-login-agent@.service" \
        "$UNIT_DIR/moondeck-login-disarm.service"
    systemctl daemon-reload
    rm -f "$AGENT_TARGET"
    rm -rf "$CONFIG_DIR" /var/lib/moondeck-login-agent
    if command -v ufw >/dev/null 2>&1; then
        while read -r number; do
            ufw --force delete "$number" >/dev/null 2>&1 || true
        done < <(ufw status numbered 2>/dev/null | grep -F "$UFW_COMMENT" |
            sed -n 's/^\[ *\([0-9]\+\)\].*/\1/p' | sort -rn)
    fi
}

apply_installation() {
    local answers=$1
    declare -A A=()
    local key value
    while IFS=$'\t' read -r key value; do
        [[ -n $key ]] && A[$key]=$value
    done <"$answers"

    # Re-running to change a setting must not invalidate a token that is
    # already on a Deck, so an existing secret wins over the fresh one.
    local secret=${A[Secret]}
    if [[ -r $CONFIG_DIR/secret ]]; then
        secret=$(cat "$CONFIG_DIR/secret")
        printf '%s\n' "$(t host_secret_kept)" >&2
    fi

    install -D -m 755 "$HOST_DIR/moondeck-login-agent" "$AGENT_TARGET"
    install -d -m 755 "$CONFIG_DIR"
    {
        printf '# written by install-host.sh\n'
        printf 'User=%s\n' "${A[User]}"
        printf 'Session=%s\n' "${A[Session]}"
        if [[ -n ${A[NtfyTopic]:-} ]]; then
            printf 'NtfyServer=%s\n' "${A[NtfyServer]}"
            printf 'NtfyTopic=%s\n' "${A[NtfyTopic]}"
            printf 'NtfyTitle=%s\n' "${A[NtfyTitle]}"
            printf 'NtfyMessage=%s\n' "${A[NtfyMessage]}"
            printf 'NtfyMessageNoStream=%s\n' "${A[NtfyMessageNoStream]}"
            printf 'NtfyMessageFailed=%s\n' "${A[NtfyMessageFailed]}"
            printf '# Port that has to answer before the ready push goes out, 0 skips the wait.\n'
            printf 'ReadyPort=47989\n'
        fi
    } >"$CONFIG_DIR/config"
    chmod 644 "$CONFIG_DIR/config"
    install -m 600 /dev/null "$CONFIG_DIR/secret"
    printf '%s' "$secret" >"$CONFIG_DIR/secret"

    sed "s/@PORT@/${A[Port]}/" "$HOST_DIR/moondeck-login-agent.socket" \
        >"$UNIT_DIR/moondeck-login-agent.socket"
    install -m 644 "$HOST_DIR/moondeck-login-agent@.service" \
        "$UNIT_DIR/moondeck-login-agent@.service"
    install -m 644 "$HOST_DIR/moondeck-login-disarm.service" \
        "$UNIT_DIR/moondeck-login-disarm.service"

    systemctl daemon-reload
    systemctl enable --now moondeck-login-agent.socket >/dev/null
    systemctl enable moondeck-login-disarm.service >/dev/null

    if [[ -n ${A[Subnet]:-} ]] && command -v ufw >/dev/null 2>&1 &&
        ufw status 2>/dev/null | grep -qi '^Status: active'; then
        ufw allow from "${A[Subnet]}" to any port "${A[Port]}" proto tcp \
            comment "$UFW_COMMENT" >/dev/null
    fi

    printf '%s\n' "$secret"
}

case $MODE in
    apply)
        ((EUID == 0)) || fail "$(t host_need_root)"
        apply_installation "$2"
        exit 0
        ;;
    apply-uninstall)
        ((EUID == 0)) || fail "$(t host_need_root)"
        remove_everything
        exit 0
        ;;
esac

# --- the half that talks to you ----------------------------------------------

run_privileged() {
    printf '%s\n' "$(t host_sudo_hint)" >&2
    sudo MOONDECK_SWITCHBOT_LANG="$MSB_LANG" bash "$SELF_PATH" "$@"
}

local_address() {
    ip -4 -o addr show scope global 2>/dev/null |
        awk '$2 !~ /^(docker|virbr|br-)/ {split($4, a, "/"); print a[1]; exit}'
}

# Everything the Deck needs in a single string, so nothing has to be retyped on
# a handheld. Values travel in the environment rather than in the argument
# list, which would show up in the process list. The address is only a
# fallback, see the wake-up script for the order the addresses are tried in.
pairing_token() {
    MSB_T_HOST=$(local_address) \
        MSB_T_PORT=$1 \
        MSB_T_SECRET=$2 \
        MSB_T_SBTOKEN=${3:-} \
        MSB_T_SBSECRET=${4:-} \
        MSB_T_DEVICE=${5:-} \
        MSB_T_COMMAND=${6:-} \
        python3 -c '
import base64
import json
import os

fields = {
    "host": "MSB_T_HOST", "port": "MSB_T_PORT", "secret": "MSB_T_SECRET",
    "sbToken": "MSB_T_SBTOKEN", "sbSecret": "MSB_T_SBSECRET",
    "device": "MSB_T_DEVICE", "command": "MSB_T_COMMAND",
}
data = {"v": 2}
for key, variable in fields.items():
    value = os.environ.get(variable, "")
    if value:
        data[key] = value
raw = json.dumps(data, separators=(",", ":")).encode("utf-8")
print(base64.b64encode(raw).decode("ascii"))
'
}

# The token is long and has to be copied, so it belongs in a text field rather
# than a message box, and on the clipboard when that is possible at all.
show_token() {
    local key=$1 token=$2 note=""
    ui_clipboard "$token" && note=$(t host_token_clipboard)
    ui_text_output "$TITLE" "$(t "$key" "$note")" "$token"
}

if [[ $MODE == uninstall ]]; then
    run_privileged --apply-uninstall || fail "$(t host_privileged_failed)"
    ui_info "$TITLE" "$(t host_uninstall_done)"
    exit 0
fi

if [[ $MODE == token ]]; then
    printf '%s\n' "$(t host_sudo_hint)" >&2
    secret=$(sudo cat "$CONFIG_DIR/secret" 2>/dev/null) || fail "$(t host_not_installed)"
    [[ -n $secret ]] || fail "$(t host_not_installed)"
    port=$(sudo sed -n 's/^ListenStream=//p' \
        "$UNIT_DIR/moondeck-login-agent.socket" 2>/dev/null | tail -1)
    show_token host_token "$(pairing_token "${port:-58471}" "$secret")"
    exit 0
fi

for dependency in python3 systemctl openssl loginctl sudo; do
    command -v "$dependency" >/dev/null 2>&1 || fail "$(t dep_missing "$dependency")"
done

ui_info "$TITLE" "$(t host_welcome)"

target_user=$(ui_input "$TITLE" "$(t host_ask_user)" "${SUDO_USER:-${USER:-}}") || abort
[[ -n $target_user ]] || abort
id -u "$target_user" >/dev/null 2>&1 || fail "$(t host_unknown_user "$target_user")"

session_choices=()
for session in /usr/share/wayland-sessions/*.desktop /usr/share/xsessions/*.desktop; do
    [[ -e $session ]] || continue
    name=${session##*/}
    case $session in
        */wayland-sessions/*) label="$name (Wayland)" ;;
        *) label="$name (X11)" ;;
    esac
    if [[ $name == plasma.desktop ]]; then
        session_choices=("$name" "$label" "${session_choices[@]}")
    else
        session_choices+=("$name" "$label")
    fi
done
((${#session_choices[@]} > 0)) || fail "$(t host_no_sessions)"

target_session=$(ui_choose "$TITLE" "$(t host_ask_session)" "${session_choices[@]}") || abort
[[ -n $target_session ]] || abort

port=$(ui_input "$TITLE" "$(t host_ask_port)" "58471") || abort
[[ $port =~ ^[0-9]+$ ]] && ((port > 0 && port < 65536)) || fail "$(t host_bad_port "$port")"

ntfy_topic=""
ntfy_server=""
if ui_yesno "$TITLE" "$(t host_ntfy_ask)"; then
    ntfy_topic=$(ui_input "$TITLE" "$(t host_ntfy_topic)" "") || abort
    [[ -n $ntfy_topic ]] || fail "$(t input_empty)"
    ntfy_server=$(ui_input "$TITLE" "$(t host_ntfy_server)" "https://ntfy.sh") || abort
fi

sb_token=""
sb_secret=""
sb_device=""
sb_command=""
if ui_yesno "$TITLE" "$(t host_sb_ask)"; then
    ui_info "$TITLE" "$(t host_creds_intro)"
    while true; do
        sb_token=$(ui_password "$TITLE" "$(t ask_token)") || abort
        [[ -n $sb_token ]] || fail "$(t input_empty)"
        sb_secret=$(ui_password "$TITLE" "$(t ask_secret)") || abort
        [[ -n $sb_secret ]] || fail "$(t input_empty)"

        devices_file=$(mktemp)
        if ! ui_progress_run "$(t fetching)" "$devices_file" sb_curl "$sb_token" "$sb_secret" "/devices"; then
            rm -f "$devices_file"
            ui_error "$TITLE" "$(t api_unreachable)"
            continue
        fi
        mapfile -t device_lines < <(sb_parse_devices <"$devices_file")
        rm -f "$devices_file"

        if [[ ${device_lines[0]:-} == ERR* ]]; then
            IFS=$'\t' read -r _ status_code message <<<"${device_lines[0]}"
            ui_error "$TITLE" "$(t api_error "$status_code" "$message")"
            continue
        fi
        ((${#device_lines[@]} > 1)) || fail "$(t no_devices)"
        break
    done

    device_choices=()
    for line in "${device_lines[@]:1}"; do
        IFS=$'\t' read -r device_id device_name device_type <<<"$line"
        device_choices+=("$device_id" "$device_name ($device_type)")
    done
    sb_device=$(ui_choose "$TITLE" "$(t choose_device)" "${device_choices[@]}") || abort
    [[ -n $sb_device ]] || abort
    sb_command=$(ui_choose "$TITLE" "$(t ask_mode)" \
        press "$(t mode_press)" turnOn "$(t mode_switch)") || abort
    [[ -n $sb_command ]] || abort
fi

# 128 bit is plenty for an HMAC key and keeps the pairing token short enough
# to be pasted comfortably on a handheld.
generated_secret=$(openssl rand -hex 16)

subnet=""
address=$(ip -4 -o addr show scope global 2>/dev/null |
    awk '$2 !~ /^(docker|virbr|br-)/ {print $4; exit}')
if [[ -n $address ]]; then
    subnet=$(python3 -c 'import ipaddress,sys; print(ipaddress.ip_network(sys.argv[1], strict=False))' "$address")
fi

answers=$(mktemp)
chmod 600 "$answers"
{
    printf 'User\t%s\n' "$target_user"
    printf 'Session\t%s\n' "$target_session"
    printf 'Port\t%s\n' "$port"
    printf 'Secret\t%s\n' "$generated_secret"
    printf 'Subnet\t%s\n' "$subnet"
    if [[ -n $ntfy_topic ]]; then
        printf 'NtfyServer\t%s\n' "${ntfy_server:-https://ntfy.sh}"
        printf 'NtfyTopic\t%s\n' "$ntfy_topic"
        printf 'NtfyTitle\t%s\n' "$(t host_ntfy_title)"
        printf 'NtfyMessage\t%s\n' "$(t host_ntfy_ready "$(uname -n)")"
        printf 'NtfyMessageNoStream\t%s\n' "$(t host_ntfy_nostream "$(uname -n)")"
        printf 'NtfyMessageFailed\t%s\n' "$(t host_ntfy_failed "$(uname -n)")"
    fi
} >"$answers"

effective_secret=$(run_privileged --apply "$answers") || {
    rm -f "$answers"
    fail "$(t host_privileged_failed)"
}
rm -f "$answers"
[[ -n $effective_secret ]] || fail "$(t host_privileged_failed)"

[[ -n $subnet ]] && ui_info "$TITLE" "$(t host_ufw_added "$subnet" "$port")"

# Autologin means PAM never sees a password, so anything that would normally be
# unlocked with it stays locked. Better to say so now than to have a password
# dialog appear out of nowhere later.
user_home=$(getent passwd "$target_user" | cut -d: -f6)
locked_stores=""
if compgen -G "$user_home/.local/share/keyrings/*.keyring" >/dev/null 2>&1; then
    locked_stores="gnome-keyring"
fi
if compgen -G "$user_home/.local/share/kwalletd/*.kwl" >/dev/null 2>&1; then
    locked_stores="${locked_stores:+$locked_stores, }KWallet"
fi
[[ -n $locked_stores ]] && ui_info "$TITLE" "$(t host_keyring_warning "$locked_stores")"

show_token host_done "$(pairing_token "$port" "$effective_secret" \
    "$sb_token" "$sb_secret" "$sb_device" "$sb_command")"
