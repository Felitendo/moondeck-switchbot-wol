#!/usr/bin/env bash
#
# Installs moondeck-switchbot-wol for the Steam Deck, into ~/.local.
#
#   curl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --uninstall
#
# SteamOS has no make and no package for this, so this does what
# `make install PREFIX=~/.local` would, minus the PC's side. Its root file
# system is replaced by every update, so the home is the only place that
# stays. Run from a checkout it installs that checkout; piped from curl it
# fetches the latest release.
#
# Copyright (C) 2026 Felitendo
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

REPO="https://github.com/Felitendo/moondeck-switchbot-wol"
API="https://api.github.com/repos/Felitendo/moondeck-switchbot-wol"

PREFIX="$HOME/.local"
BINDIR="$PREFIX/bin"
LIBEXECDIR="$PREFIX/lib/moondeck-switchbot-wol"
LIBDIR="$PREFIX/share/moondeck-switchbot-wol/lib"
LOCALEDIR="$PREFIX/share/locale"
CONFDIR="${XDG_CONFIG_HOME:-$HOME/.config}/moondeck-switchbot-wol"
STATEDIR="${XDG_STATE_HOME:-$HOME/.local/state}/moondeck-switchbot-wol"

say() { printf '%s\n' "$*"; }
die() { printf 'moondeck-switchbot-wol: %s\n' "$*" >&2; exit 1; }

# The newest release, or main while there is none.
latest_ref() {
	local tag
	tag="$(curl -fsSL "$API/releases/latest" 2>/dev/null \
		| python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])' 2>/dev/null)" || tag=''
	printf '%s\n' "${tag:-main}"
}

# fetch <dir>
# Unpacks the source into <dir> and prints where it ended up.
fetch() {
	local dir="$1" ref
	ref="$(latest_ref)"
	say "Downloading $ref..." >&2
	curl -fsSL "$REPO/archive/$ref.tar.gz" | tar -xz -C "$dir" \
		|| die "could not download $REPO/archive/$ref.tar.gz"
	printf '%s\n' "$dir"/*/
}

install_from() {
	local src="$1" version f l

	# Written down in the Makefile, see `make version`.
	version="$(sed -n 's/^VERSION *?= *//p' "$src/Makefile")"
	install -Dm755 "$src/src/moondeck-switchbot-wol" "$BINDIR/moondeck-switchbot-wol"
	install -Dm755 "$src/src/wake" "$LIBEXECDIR/wake"
	install -d "$LIBDIR"
	install -m644 "$src"/src/lib/*.sh "$src"/src/lib/*.py "$LIBDIR/"

	for f in "$BINDIR/moondeck-switchbot-wol" "$LIBEXECDIR/wake" "$LIBDIR"/*.sh; do
		sed -i -e "s|@VERSION@|$version|g" \
		       -e "s|@BINDIR@|$BINDIR|g" \
		       -e "s|@LIBDIR@|$LIBDIR|g" \
		       -e "s|@LIBEXECDIR@|$LIBEXECDIR|g" \
		       -e "s|@LOCALEDIR@|$LOCALEDIR|g" "$f"
	done

	# Translations need msgfmt. Without it everything is in English.
	if command -v msgfmt > /dev/null 2>&1; then
		for f in "$src"/po/*.po; do
			l="$(basename "$f" .po)"
			mkdir -p "$LOCALEDIR/$l/LC_MESSAGES"
			msgfmt -o "$LOCALEDIR/$l/LC_MESSAGES/moondeck-switchbot-wol.mo" "$f"
		done
	fi
}

uninstall() {
	# MoonDeck gets its own Wake-on-LAN back before the shim disappears.
	if [[ -x $BINDIR/moondeck-switchbot-wol ]]; then
		"$BINDIR/moondeck-switchbot-wol" disable || true
	fi
	rm -f "$BINDIR/moondeck-switchbot-wol"
	rm -rf "$LIBEXECDIR" "$PREFIX/share/moondeck-switchbot-wol"
	rm -f "$LOCALEDIR"/*/LC_MESSAGES/moondeck-switchbot-wol.mo
	# The config holds the SwitchBot credentials, so it goes too.
	rm -rf "$CONFDIR" "$STATEDIR"
	say "Removed moondeck-switchbot-wol and its settings."
}

main() {
	local here='' tmp='' src cmd

	(( EUID != 0 )) || die "run this as your own user, not as root"

	if [[ ${1:-} == --uninstall ]]; then
		uninstall
		return
	fi

	for cmd in curl tar python3; do
		command -v "$cmd" > /dev/null 2>&1 || die "$cmd is missing"
	done

	# A checkout next to this script is installed as it is.
	if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
		here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	fi
	if [[ -n $here && -f $here/src/moondeck-switchbot-wol ]]; then
		src="$here"
	else
		tmp="$(mktemp -d)"
		src="$(fetch "$tmp")"
	fi

	install_from "$src"
	[[ -n $tmp ]] && rm -rf "$tmp"
	say "Installed $BINDIR/moondeck-switchbot-wol"

	# Straight into the menu, with the keyboard rather than the pipe this
	# script came through.
	if (: < /dev/tty) 2> /dev/null; then
		exec "$BINDIR/moondeck-switchbot-wol" < /dev/tty > /dev/tty
	fi
	say "Run it with: $BINDIR/moondeck-switchbot-wol"
}

# Everything is in a function, so bash has read the whole script before it
# runs any of it, even when it comes through a pipe.
main "$@"
