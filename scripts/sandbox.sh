#!/usr/bin/env bash
# Runs the checkout in a throwaway sandbox: its own config and state, a MoonDeck
# with one PC, and the host side as a dry run. Writes nothing outside of it.
#
#   scripts/sandbox.sh [command]          the Deck's side
#   scripts/sandbox.sh host [command]     the PC's side
#   scripts/sandbox.sh --shim <args>      what MoonDeck runs
#
# The SwitchBot API is the real one, unless MSW_SB_API points elsewhere.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
box="${MSW_SANDBOX:-${TMPDIR:-/tmp}/moondeck-switchbot-wol-sandbox}"

export XDG_CONFIG_HOME="$box/config" XDG_STATE_HOME="$box/state"
export MSW_LIBDIR="$root/src/lib" MSW_LIBEXECDIR="$root/src" MSW_BINDIR="$root/src"
export MSW_HOST_CONFDIR="$box/etc" MSW_HOST_STATEDIR="$box/var" MSW_UNITDIR="$box/units"
export MSW_DM_CONFIG="$box/plasmalogin.conf" MSW_DRY_RUN=1

mkdir -p "$XDG_CONFIG_HOME/moondeck" "$XDG_STATE_HOME"
[[ -f $XDG_CONFIG_HOME/moondeck/settings.json ]] \
	|| cp "$root/tests/moondeck-settings.json" "$XDG_CONFIG_HOME/moondeck/settings.json"

# Translations, when built.
if [[ -f $root/po/de.mo ]]; then
	mkdir -p "$box/locale/de/LC_MESSAGES"
	cp -f "$root/po/de.mo" "$box/locale/de/LC_MESSAGES/moondeck-switchbot-wol.mo"
	export MSW_LOCALEDIR="$box/locale"
fi

if [[ ${1:-} == --shim ]]; then
	shift
	exec "$root/src/wake" "$@"
fi
exec "$root/src/moondeck-switchbot-wol" "$@"
