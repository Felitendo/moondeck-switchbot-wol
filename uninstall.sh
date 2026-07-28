#!/usr/bin/env bash
#
# Removes the wake-up script and, if wanted, the stored credentials.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/i18n.sh
source "$SCRIPT_DIR/lib/i18n.sh"

for arg in "$@"; do
    case $arg in
        --cli) MSB_FORCE_CLI=1 ;;
        *) ;;
    esac
done

# shellcheck source=lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"

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
