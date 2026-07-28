#!/usr/bin/env bash
#
# Removes the wake-up script and, if wanted, the stored credentials.

set -euo pipefail

RAW_BASE=${MOONDECK_RAW_BASE:-https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main}
BOOTSTRAP_DIR=${MOONDECK_BOOTSTRAP_DIR:-}
trap 'if [[ -n $BOOTSTRAP_DIR ]]; then rm -rf "$BOOTSTRAP_DIR"; fi' EXIT

SELF_PART=uninstall.sh
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
if [[ -r ${SCRIPT_DIR:-}/lib/i18n.sh ]]; then
    ROOT_DIR=$SCRIPT_DIR
else
    bootstrap lib/i18n.sh lib/ui.sh
    ROOT_DIR=$BOOTSTRAP_DIR
fi

# shellcheck source=lib/i18n.sh
source "$ROOT_DIR/lib/i18n.sh"

for arg in "$@"; do
    case $arg in
        --cli) MSB_FORCE_CLI=1 ;;
        *) ;;
    esac
done

# shellcheck source=lib/ui.sh
source "$ROOT_DIR/lib/ui.sh"

TITLE=$(t app_title)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/moondeck-switchbot"
CONFIG_FILE="$CONFIG_DIR/config"

INSTALL_PATH=""
if [[ -r $CONFIG_FILE ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi
[[ -n $INSTALL_PATH ]] || INSTALL_PATH="$HOME/moondeck-switchbot-wol.sh"

if [[ ! -e $INSTALL_PATH && ! -e $CONFIG_FILE ]]; then
    ui_info "$TITLE" "$(t uninstall_none)"
    exit 0
fi

ui_info "$TITLE" "$(t uninstall_intro)"
rm -f "$INSTALL_PATH"
rm -f "/tmp/moondeck-switchbot-$(id -u).stamp" "/tmp/moondeck-switchbot-$(id -u).log"

if [[ -e $CONFIG_FILE ]] && ui_yesno "$TITLE" "$(t uninstall_ask_config "$CONFIG_FILE")"; then
    rm -f "$CONFIG_FILE"
    rmdir "$CONFIG_DIR" 2>/dev/null || true
fi

ui_info "$TITLE" "$(t uninstall_done)"
