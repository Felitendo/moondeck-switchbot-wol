# shellcheck shell=bash
#
# The wake-up itself: press the button, then help the PC past its login screen.
#
# MoonDeck reads what this prints until the output closes, and reports a
# non-zero exit as a failed wake-up. So the part that waits for the PC to boot
# runs on its own, detached, and writes only to the log.

# msw_press
# Presses the configured SwitchBot and remembers when. The reason for a failure
# is in MSW_SB_ERROR.
msw_press() {
	msw_sb_command "$CFG_TOKEN" "$CFG_SECRET" "$CFG_DEVICE" "$CFG_COMMAND" || return 1
	msw_state_write last_press "$(date +%s)"
}

# msw_cooldown_left
# Seconds until the button may be pressed again, 0 when it may right away.
msw_cooldown_left() {
	local last left
	last="$(msw_state_read last_press)"
	[[ $last =~ ^[0-9]+$ ]] || { printf '0\n'; return; }
	left=$(( last + CFG_COOLDOWN - $(date +%s) ))
	(( left < 0 )) && left=0
	printf '%s\n' "$left"
}

# msw_do_wake <HOSTNAME> <IP_ADDRESS> <PORT> <MAC>
# What MoonDeck runs, through the shim.
msw_do_wake() {
	local hostname="${1:-}" address="${2:-}" left

	msw_log_trim
	msw_config_load
	msw_log "MoonDeck wakes ${hostname:-?} (${address:-?})"

	if ! msw_switchbot_ready; then
		msw_log "ERROR: the SwitchBot is not set up, run $MSW_NAME"
		return 1
	fi

	# A second press switches the PC off again. MoonDeck is told to send
	# only once, and this catches what still comes twice, like the button in
	# the quick access menu right after a start.
	left="$(msw_cooldown_left)"
	if (( left > 0 )); then
		msw_log "pressed a moment ago, not again for ${left}s"
		return 0
	fi

	if ! msw_press; then
		msw_log "ERROR: $MSW_SB_ERROR"
		return 1
	fi
	msw_log "SwitchBot: $CFG_COMMAND sent to ${CFG_DEVICE_NAME:-$CFG_DEVICE}"

	if [[ -n $CFG_TRIGGER_SECRET ]]; then
		# The address MoonDeck uses goes first: it is what reaches the PC
		# today, whatever the DHCP server handed out.
		setsid -f "$MSW_SELF" knock "$address" "$hostname" \
			> /dev/null 2>&1 < /dev/null
		msw_log "waiting for the PC to boot, in the background"
	fi
	return 0
}

# msw_do_knock <address>...
# Internal: the detached half of a wake-up.
msw_do_knock() {
	local -a addresses=()
	local address line

	msw_config_load
	for address in "$@"; do
		[[ -n $address ]] && addresses+=("$address")
	done
	(( ${#addresses[@]} )) || { msw_log "login trigger: no address for the PC"; return 1; }

	MSW_TRIGGER_SECRET="$CFG_TRIGGER_SECRET" msw_python knock \
		"$CFG_TRIGGER_PORT" "$CFG_KNOCK_TIMEOUT" "${addresses[@]}" 2>&1 |
		while IFS= read -r line; do
			msw_log "login trigger: $line" > /dev/null
		done
	return "${PIPESTATUS[0]}"
}
