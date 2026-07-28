#!/usr/bin/env bash
#
# Sets up the one-shot login trigger on the host PC. Run this with sudo on the
# machine that gets woken up, not on the Steam Deck.

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

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || SCRIPT_DIR=""
if [[ -r ${SCRIPT_DIR:-}/../lib/i18n.sh ]]; then
    ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
else
    bootstrap lib/i18n.sh lib/ui.sh \
        host/install-host.sh \
        host/moondeck-login-agent \
        host/moondeck-login-agent.socket \
        host/moondeck-login-agent@.service \
        host/moondeck-login-disarm.service
    ROOT_DIR=$BOOTSTRAP_DIR
fi
HOST_DIR=$ROOT_DIR/host

# shellcheck source=../lib/i18n.sh
source "$ROOT_DIR/lib/i18n.sh"

# Dialog windows and sudo do not mix, this one stays in the terminal.
MSB_FORCE_CLI=1
# shellcheck source=../lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"

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

if ((EUID != 0)); then
    # sudo closes the file descriptor that a process substitution lives on, so
    # a downloaded copy has to be handed over as a real path.
    if [[ -n $BOOTSTRAP_DIR ]]; then
        chmod 755 "$HOST_DIR/install-host.sh"
        printf '%s\n' "$(t host_elevating)"
        exec sudo MOONDECK_RAW_BASE="$RAW_BASE" MOONDECK_BOOTSTRAP_DIR="$BOOTSTRAP_DIR" \
            bash "$HOST_DIR/install-host.sh" "$@"
    fi
    fail "$(t host_need_root)"
fi

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
    ui_info "$TITLE" "$(t host_uninstall_done)"
}

if [[ ${1:-} == --uninstall ]]; then
    remove_everything
    exit 0
fi

for dependency in python3 systemctl openssl loginctl; do
    command -v "$dependency" >/dev/null 2>&1 || fail "$(t dep_missing "$dependency")"
done

ui_info "$TITLE" "$(t host_welcome)"

target_user=$(ui_input "$TITLE" "$(t host_ask_user)" "${SUDO_USER:-}") || abort
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

secret=$(openssl rand -hex 32)

install -D -m 755 "$HOST_DIR/moondeck-login-agent" "$AGENT_TARGET"
install -d -m 755 "$CONFIG_DIR"
printf '# written by install-host.sh\nUser=%s\nSession=%s\n' \
    "$target_user" "$target_session" >"$CONFIG_DIR/config"
chmod 644 "$CONFIG_DIR/config"
install -m 600 /dev/null "$CONFIG_DIR/secret"
printf '%s' "$secret" >"$CONFIG_DIR/secret"

sed "s/@PORT@/$port/" "$HOST_DIR/moondeck-login-agent.socket" \
    >"$UNIT_DIR/moondeck-login-agent.socket"
install -m 644 "$HOST_DIR/moondeck-login-agent@.service" \
    "$UNIT_DIR/moondeck-login-agent@.service"
install -m 644 "$HOST_DIR/moondeck-login-disarm.service" \
    "$UNIT_DIR/moondeck-login-disarm.service"

systemctl daemon-reload
systemctl enable --now moondeck-login-agent.socket >/dev/null
systemctl enable moondeck-login-disarm.service >/dev/null

subnet=""
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    address=$(ip -4 -o addr show scope global 2>/dev/null |
        awk '$2 !~ /^(docker|virbr|br-)/ {print $4; exit}')
    if [[ -n $address ]]; then
        subnet=$(python3 -c 'import ipaddress,sys; print(ipaddress.ip_network(sys.argv[1], strict=False))' "$address")
        ufw allow from "$subnet" to any port "$port" proto tcp comment "$UFW_COMMENT" >/dev/null
    fi
fi

address_hint=$(ip -4 -o addr show scope global 2>/dev/null |
    awk '$2 !~ /^(docker|virbr|br-)/ {split($4, a, "/"); print a[1]; exit}')

if [[ -n $subnet ]]; then
    ui_info "$TITLE" "$(t host_ufw_added "$subnet" "$port")"
else
    ui_info "$TITLE" "$(t host_ufw_skipped "$port")"
fi

ui_info "$TITLE" "$(t host_done "$address_hint" "$port" "$secret")"
