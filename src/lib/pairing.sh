# shellcheck shell=bash
#
# Pairing: everything the Deck needs from the PC, in one line.
#
# The line is made on the PC, where there is a real keyboard. It always carries
# the login trigger and, when wanted, the SwitchBot setup too, so nothing has
# to be typed on the Deck. The PC finds the Deck on its network and sends it
# over, see pair.py. Where it cannot, the line is pasted on the Deck instead,
# as a pairing code.
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

# ---------------------------------------------------------------------------
# Over the network
# ---------------------------------------------------------------------------

# Where the Deck waits for the PC, and how long either end waits for the other.
MSW_PAIR_PORT=$(( MSW_DEFAULT_PORT + 1 ))
MSW_PAIR_WAIT=300

MSW_PAIR_PID=''
MSW_PAIR_CODE=''

# msw_pair_start <pair.py arguments...>
# Runs pair.py next to the menu. Its events come in on MSW_PAIR_IN, the
# answers go out on MSW_PAIR_OUT. The code to send is taken from MSW_PAIR_CODE,
# so it stays out of the process list.
msw_pair_start() {
	coproc MSW_PAIR_PROC {
		MSW_PAIR_CODE="$MSW_PAIR_CODE" exec python3 "$MSW_LIBDIR/pair.py" "$@" 2> /dev/null
	}
	MSW_PAIR_PID="$MSW_PAIR_PROC_PID"
	# Copies, because bash closes the coprocess's own as soon as it ends.
	exec {MSW_PAIR_IN}<&"${MSW_PAIR_PROC[0]}" {MSW_PAIR_OUT}>&"${MSW_PAIR_PROC[1]}"
}

msw_pair_stop() {
	[[ -n $MSW_PAIR_PID ]] || return 0
	kill "$MSW_PAIR_PID" 2> /dev/null
	wait "$MSW_PAIR_PID" 2> /dev/null
	exec {MSW_PAIR_IN}<&- {MSW_PAIR_OUT}>&-
	MSW_PAIR_PID=''
}

# msw_pair_answer <answer>
msw_pair_answer() {
	printf '%s\n' "$1" >&"$MSW_PAIR_OUT"
}

# msw_pair_next
# The next event from pair.py in MSW_PAIR_EVENT, the rest of its line in
# MSW_PAIR_ARGS. A key pressed meanwhile is the event KEY, with the key in
# MSW_KEY. When pair.py ends, the event is END.
msw_pair_next() {
	local line rc

	while true; do
		IFS= read -r -t 0.2 -u "$MSW_PAIR_IN" line
		rc=$?
		if (( rc == 0 )); then
			MSW_PAIR_EVENT="${line%% *}"
			MSW_PAIR_ARGS=''
			[[ $line == *' '* ]] && MSW_PAIR_ARGS="${line#* }"
			return 0
		fi
		# Above 128 is the timeout, so pair.py is still there.
		if (( rc < 128 )); then
			MSW_PAIR_EVENT=END
			return 0
		fi
		if msw_read_key 0.05; then
			MSW_PAIR_EVENT=KEY
			return 0
		fi
	done
}
