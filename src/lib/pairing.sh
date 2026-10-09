# shellcheck shell=bash
#
# The pairing code: everything the Deck needs from the PC, in one line.
#
# It is made on the PC, where there is a real keyboard, and pasted on the Deck,
# where there is not. It always carries the login trigger and, when wanted,
# the SwitchBot setup too, so nothing has to be typed on the Deck.
#
# Format: "msw1:" and the base64 of "Key=Value" lines, with the same keys as
# the Deck's config. Only the keys below are read from a code.

MSW_PAIR_KEYS=" TriggerPort TriggerSecret Token Secret Device DeviceName Command "

declare -A MSW_PAIR=()

# msw_pair_encode <Key=Value>...
# Empty values are left out.
msw_pair_encode() {
	local pair lines=''
	for pair in "$@"; do
		[[ -n ${pair#*=} ]] && lines+="$pair"$'\n'
	done
	printf 'msw1:%s\n' "$(printf '%s' "$lines" | base64 -w0)"
}

# msw_pair_decode <code>
# The keys in MSW_PAIR. Returns 1 for anything that is not a code. Line breaks
# and spaces are dropped first: a long line pasted from a terminal can arrive
# broken up.
msw_pair_decode() {
	local code="${1//[[:space:]]/}" raw line key

	MSW_PAIR=()
	[[ $code == msw1:* ]] || return 1
	raw="$(printf '%s' "${code#msw1:}" | base64 -d 2>/dev/null)" || return 1

	while IFS= read -r line; do
		[[ $line == *=* ]] || continue
		key="${line%%=*}"
		[[ $MSW_PAIR_KEYS == *" $key "* ]] && MSW_PAIR[$key]="${line#*=}"
	done <<< "$raw"

	[[ ${MSW_PAIR[TriggerSecret]:-} =~ ^[0-9a-f]{32,}$ ]] || return 1
	[[ ${MSW_PAIR[TriggerPort]:-} =~ ^[0-9]+$ ]] || return 1
}

# msw_pair_has_switchbot
# Whether the decoded code carries the SwitchBot setup as well.
msw_pair_has_switchbot() {
	[[ -n ${MSW_PAIR[Token]:-} && -n ${MSW_PAIR[Secret]:-} && -n ${MSW_PAIR[Device]:-} ]]
}

# msw_pair_apply
# Writes the decoded code into the Deck's config. A code without the SwitchBot
# setup leaves the one that is there alone.
msw_pair_apply() {
	local key
	for key in "${!MSW_PAIR[@]}"; do
		msw_config_set "$key" "${MSW_PAIR[$key]}" || return 1
	done
}
