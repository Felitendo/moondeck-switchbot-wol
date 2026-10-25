# shellcheck shell=bash
#
# The menus, one for each end.
#
# They are the whole interface. Each shows what is set up right now on top,
# and below it a handful of keys. `moondeck-switchbot-wol` opens the Deck's,
# `moondeck-switchbot-wol host` the PC's.

# ---------------------------------------------------------------------------
# SwitchBot, asked on either end
# ---------------------------------------------------------------------------

# msw_ui_switchbot <where>
# Asks for the credentials, fetches the devices and lets one be picked. The
# answers in SB_TOKEN, SB_SECRET, SB_DEVICE, SB_DEVICE_NAME and SB_COMMAND.
# <where> says where the credentials end up. Returns 1 when cancelled.
msw_ui_switchbot() {
	local where="$1" id name type title
	local -a choices=()
	local -A names=()

	msw_ui_begin
	title="$(msw_msg "SwitchBot")"
	msw_ui_screen "$title"
	msw_ui_text "$(msw_msg "This needs the token and the secret of your SwitchBot account. In the SwitchBot app, go to Profile, Preferences, tap App Version 10 times, then open Developer Options.")"
	printf '\n'
	msw_ui_text "$where"

	while true; do
		msw_ui_line "$(msw_msg "Token:")" '' secret || { msw_ui_end; return 1; }
		SB_TOKEN="${MSW_LINE//[[:space:]]/}"
		msw_ui_line "$(msw_msg "Secret:")" '' secret || { msw_ui_end; return 1; }
		SB_SECRET="${MSW_LINE//[[:space:]]/}"

		printf '\n  %s\n' "$(msw_dim "$(msw_msg "Asking SwitchBot for your devices...")")"
		if [[ -n $SB_TOKEN && -n $SB_SECRET ]] && msw_sb_devices "$SB_TOKEN" "$SB_SECRET"; then
			[[ -n $MSW_SB_DEVICES ]] && break
			MSW_SB_ERROR="$(msw_msg "Your account has no devices. A Bot shows up once it is paired with a SwitchBot hub and Cloud Services is on for it in the app.")"
		fi
		printf '\n'
		msw_ui_text "$MSW_C_RED${MSW_SB_ERROR:-$(msw_msg "Nothing entered.")}$MSW_C_RESET"
		msw_ui_yesno "$(msw_msg "Try again?")" || { msw_ui_end; return 1; }
	done

	while IFS=$'\t' read -r id name type; do
		choices+=("$id" "$name $(msw_dim "($type)")")
		names[$id]="$name"
	done <<< "$MSW_SB_DEVICES"

	msw_ui_pick "$title" "$(msw_msg "Which device presses the power button?")" "${choices[@]}" \
		|| { msw_ui_end; return 1; }
	SB_DEVICE="$MSW_PICKED"
	SB_DEVICE_NAME="${names[$SB_DEVICE]}"

	msw_ui_pick "$title" "$(msw_msg "How is it set up in the SwitchBot app?")" \
		press  "$(msw_msg "Press mode: the arm pushes and comes back (recommended)")" \
		turnOn "$(msw_msg "Switch mode, or a smart plug: switch on")" \
		|| { msw_ui_end; return 1; }
	SB_COMMAND="$MSW_PICKED"
	msw_ui_end
}

# ---------------------------------------------------------------------------
# Settings, on either end
# ---------------------------------------------------------------------------

# msw_ui_settings <file> <setter> <spec>...
# A cursor list. Each spec is "Key|type|default|label|help", type is seconds,
# port, text, user or secret. Returns 0 when something was changed.
msw_ui_settings() {
	local file="$1" setter="$2" spec key type default label help
	local i count cursor=0 touched=0 width=0 frame row pad marker value
	local selected="${MSW_C_BLUE}▸${MSW_C_RESET} " none hint
	local -a keys=() types=() defaults=() labels=() helps=()
	shift 2

	for spec in "$@"; do
		IFS='|' read -r key type default label help <<< "$spec"
		keys+=("$key") types+=("$type") defaults+=("$default") labels+=("$label") helps+=("$help")
		(( ${#label} > width )) && width=${#label}
	done
	count=${#keys[@]}

	msw_msg_into "(none)"; none="$MSW_MSG_RESULT"
	msw_msg_into "Up/Down: select, Enter: change, Esc: back"; hint="$MSW_MSG_RESULT"

	msw_ui_begin
	while true; do
		frame="$(msw_ui_screen "$(msw_msg "Settings")")"$'\n'
		for (( i = 0; i < count; i++ )); do
			msw_conf_get "$file" "${keys[i]}" "${defaults[i]}"
			value="$MSW_CONF_VALUE"
			case ${types[i]} in
				secret)  value="••••••••" ;;
				seconds) value="$(msw_msg "%s seconds" "$value")" ;;
			esac
			[[ -n $value ]] || value="${MSW_C_DIM}${none}${MSW_C_RESET}"
			pad=$(( width + 3 - ${#labels[i]} ))
			if (( i == cursor )); then marker="$selected"; else marker='  '; fi
			printf -v row '  %s%s%*s %s' "$marker" "${labels[i]}" "$pad" '' "$value"
			frame+="$row"$'\n'
		done
		frame+=$'\n'"$(msw_ui_text "${helps[cursor]}")"$'\n\n'"  ${MSW_C_DIM}${hint}${MSW_C_RESET}"$'\n'
		printf '%s' "$frame"

		msw_read_key || break
		case $MSW_KEY in
			up|k)   cursor=$(( (cursor - 1 + count) % count )) ;;
			down|j) cursor=$(( (cursor + 1) % count )) ;;
			enter|space|right)
				_msw_ui_setting_edit "$file" "$setter" "${keys[cursor]}" "${types[cursor]}" \
					"${defaults[cursor]}" "${labels[cursor]}" && touched=1
				;;
			escape|left|q|Q) break ;;
		esac
	done
	msw_ui_end
	(( touched ))
}

_msw_ui_setting_edit() {
	local file="$1" setter="$2" key="$3" type="$4" default="$5" label="$6" user
	local -a users=()

	msw_conf_get "$file" "$key" "$default"
	case $type in
		user)
			while IFS= read -r user; do
				users+=("$user" "$user")
			done < <(msw_login_users)
			msw_ui_pick "$label" '' "${users[@]}" || return 1
			"$setter" "$key" "$MSW_PICKED"
			;;
		secret)
			msw_ui_yesno "$(msw_msg "Make a new secret? The Deck has to be paired again.")" || return 1
			msw_host_secret_new
			;;
		*)
			msw_ui_line "$label" "$MSW_CONF_VALUE" || return 1
			case $type in
				seconds) [[ $MSW_LINE =~ ^[0-9]+$ ]] || return 1 ;;
				port)    [[ $MSW_LINE =~ ^[0-9]+$ ]] && (( MSW_LINE > 0 && MSW_LINE < 65536 )) || return 1 ;;
			esac
			"$setter" "$key" "$MSW_LINE"
			;;
	esac
}

# ---------------------------------------------------------------------------
# The Deck
# ---------------------------------------------------------------------------

# msw_ui_status
# Shared by `status` and the menu. Reads MoonDeck's settings every time, so it
# says what MoonDeck will actually do.
msw_ui_status() {
	local wake=no

	msw_config_load
	msw_moondeck_load && wake="$MD_OURS"

	msw_row "$(msw_msg "SwitchBot wake-up")" "$(msw_onoff "$wake")"
	printf '\n'

	if msw_switchbot_ready; then
		msw_row "$(msw_msg "SwitchBot")" \
			"${CFG_DEVICE_NAME:-$CFG_DEVICE} $(msw_dim "($(msw_sb_command_label "$CFG_COMMAND"))")"
	else
		msw_row "$(msw_msg "SwitchBot")" "$(msw_warn "$(msw_msg "not set up")")"
	fi

	case $MD_STATE in
		ok)      msw_row "$(msw_msg "MoonDeck")" "$MD_NAME $(msw_dim "($MD_ADDRESS)")" ;;
		nohost)  msw_row "$(msw_msg "MoonDeck")" "$(msw_warn "$(msw_msg "no PC added yet")")" ;;
		*)       msw_row "$(msw_msg "MoonDeck")" "$(msw_warn "$(msw_msg "not found")")" ;;
	esac

	if [[ -n $CFG_TRIGGER_SECRET ]]; then
		msw_row "$(msw_msg "Login on the PC")" "$(msw_msg "paired")"
	else
		msw_row "$(msw_msg "Login on the PC")" "$(msw_dim "$(msw_msg "not paired")")"
	fi

	msw_row "$(msw_msg "Last press")" "$(msw_time_ago "$(msw_state_read last_press)")"
}

# msw_ui_pair
# Waits for the PC to find this Deck, and saves what it sends. Returns 0 once
# paired.
msw_ui_pair() {
	local title rc=1 digits address name

	title="$(msw_msg "Pair with the PC")"
	msw_ui_screen "$title"
	msw_ui_text "$(msw_msg "On the PC, run this and press 2:")"
	printf '\n    %s\n\n' "$MSW_C_BOLD$MSW_NAME host$MSW_C_RESET"
	msw_ui_text "$(msw_msg "The PC finds this Deck on its own.")"
	printf '\n  %s\n\n  %s\n' "$(msw_msg "Waiting for the PC...")" \
		"$(msw_dim "$(msw_msg "c: paste a pairing code instead, Esc: back")")"

	msw_pair_start listen "$MSW_PAIR_PORT" "$MSW_PAIR_WAIT"
	while msw_pair_next; do
		case $MSW_PAIR_EVENT in
			KEY)
				case $MSW_KEY in
					c|C)
						msw_pair_stop
						msw_ui_pair_code
						return
						;;
					escape|q|Q) break ;;
				esac
				;;
			PEER)
				read -r digits address name <<< "$MSW_PAIR_ARGS"
				msw_ui_screen "$title"
				msw_ui_text "$(msw_msg "%s (%s) wants to pair. It shows a code too:" "$name" "$address")"
				msw_ui_digits "$digits"
				if ! msw_ui_yesno "$(msw_msg "Is it the same code?")"; then
					# The PC hears so before pair.py is done.
					msw_pair_answer no
					msw_ui_bad "$(msw_msg "Not paired.")"
					continue
				fi
				msw_pair_answer yes
				printf '\n  %s\n' "$(msw_dim "$(msw_msg "Waiting for the PC...")")"
				;;
			DATA)
				if msw_ui_run msw_do_pair "$MSW_PAIR_ARGS"; then
					msw_pair_answer ok
					rc=0
				else
					msw_pair_answer fail
				fi
				;;
			DONE) break ;;
			CANCELLED)
				msw_ui_bad "$(msw_msg "The PC said no.")"
				break
				;;
			TIMEOUT)
				msw_ui_bad "$(msw_msg "No PC came in %s minutes." "$(( MSW_PAIR_WAIT / 60 ))")"
				break
				;;
			*)
				msw_ui_bad "$(msw_msg "Pairing did not work: %s" "${MSW_PAIR_ARGS:-$MSW_PAIR_EVENT}")"
				break
				;;
		esac
	done
	msw_pair_stop
	return "$rc"
}

# For a PC that cannot reach the Deck, like on a guest network.
msw_ui_pair_code() {
	msw_ui_screen "$(msw_msg "Pair with a code")"
	msw_ui_text "$(msw_msg "When the PC does not find this Deck, it shows a pairing code. Copy the line that starts with msw1: and paste it here. In Konsole, paste with Ctrl+Shift+V.")"
	msw_ui_line "$(msw_msg "Pairing code:")" '' secret || return 1
	msw_ui_run msw_do_pair "$MSW_LINE"
}

msw_ui_setup() {
	msw_ui_switchbot "$(msw_msg "They stay on this Deck, in %s, and only ever go to SwitchBot." "$MSW_CONFIG")" \
		|| return 1
	msw_ui_run msw_sb_save
}

# The switch on the front screen. Turning it on when there is no SwitchBot yet
# starts with that, so pressing 1 is all a first start needs.
msw_ui_toggle() {
	local title

	msw_config_load
	msw_moondeck_load
	if [[ $MD_OURS == yes ]]; then
		msw_ui_run msw_do_disable
		return
	fi

	if ! msw_switchbot_ready; then
		title="$(msw_msg "SwitchBot wake-up")"
		msw_ui_pick "$title" "$(msw_msg "First the SwitchBot. The PC can send all of it when pairing, so nothing has to be typed here.")" \
			pair  "$(msw_msg "Pair with the PC")" \
			setup "$(msw_msg "Set up the SwitchBot by hand")" \
			|| return 0
		case $MSW_PICKED in
			pair)  msw_ui_pair  || return 0 ;;
			setup) msw_ui_setup || return 0 ;;
		esac
		msw_config_load
		msw_switchbot_ready || return 0
	fi
	msw_ui_run msw_do_enable
}

MSW_DECK_SETTINGS=()

msw_ui_deck_settings() {
	MSW_DECK_SETTINGS=(
		"Cooldown|seconds|180|$(msw_msg "Press again after")|$(msw_msg "A second press switches the PC off again. MoonDeck cannot press twice within this time.")"
		"KnockTimeout|seconds|240|$(msw_msg "Wait for the PC")|$(msw_msg "How long the Deck waits for the PC to boot, to log it in.")"
	)
	msw_ui_settings "$MSW_CONFIG" msw_config_set "${MSW_DECK_SETTINGS[@]}"
}

msw_ui_menu() {
	MSW_IN_MENU=1
	msw_ui_begin

	while true; do
		msw_ui_screen "$MSW_PRETTY"
		msw_ui_status
		printf '\n'
		msw_ui_show_msg
		printf '  [1] %s\n' "$(msw_msg "Turn SwitchBot wake-up on or off")"
		printf '  [2] %s\n' "$(msw_msg "Pair with the PC")"
		printf '  [3] %s\n' "$(msw_msg "Set up the SwitchBot by hand")"
		printf '  [4] %s\n' "$(msw_msg "Press the button now")"
		printf '  [5] %s\n' "$(msw_msg "Settings")"
		printf '  [q] %s\n' "$(msw_msg "Quit")"
		printf '\n  > '

		msw_read_key || break
		case $MSW_KEY in
			1) msw_ui_toggle ;;
			2) msw_ui_pair ;;
			3) msw_ui_setup ;;
			4)
				msw_ui_yesno "$(msw_msg "The SwitchBot really presses the button. Go ahead?")" \
					&& msw_ui_run msw_do_press
				;;
			5) msw_ui_deck_settings ;;
			q|Q) break ;;
			# Anything else redraws. Esc does not quit, so a mistyped arrow
			# key cannot close the menu.
		esac
	done

	printf '\n'
	msw_ui_end
}

# ---------------------------------------------------------------------------
# The PC
# ---------------------------------------------------------------------------

# msw_ui_host_pair
# Finds the Deck on this network and sends it the pairing code. Shows the code
# instead when there is no Deck to be found.
msw_ui_host_pair() {
	local title code line address name digits
	local -a found=() choices=() targets=()

	title="$(msw_msg "Pair with the Deck")"
	msw_host_config_load
	msw_host_code_pairs || { msw_ui_bad "$(msw_msg "Could not write %s." "$MSW_HOST_SECRET")"; return 1; }

	msw_ui_screen "$title"
	msw_ui_text "$(msw_msg "This PC can send the SwitchBot setup to the Deck too. Then nothing has to be typed there. The credentials are not kept on this PC.")"
	if msw_ui_yesno "$(msw_msg "Send the SwitchBot setup too?")"; then
		msw_ui_switchbot "$(msw_msg "They are not kept on this PC. They only go to the Deck.")" || return 1
		MSW_HOST_PAIRS+=("Token=$SB_TOKEN" "Secret=$SB_SECRET" "Device=$SB_DEVICE"
			"DeviceName=$SB_DEVICE_NAME" "Command=$SB_COMMAND")
	fi
	code="$(msw_pair_encode "${MSW_HOST_PAIRS[@]}")"

	# Looks until a Deck waits, or there is no point any more.
	while true; do
		msw_ui_screen "$title"
		msw_ui_text "$(msw_msg "On the Deck, open the menu and press 2. This PC finds it on its own.")"
		printf '\n  %s\n\n  %s\n' "$(msw_msg "Looking for the Deck...")" "$(msw_dim "$(msw_msg "Esc: back")")"

		# The tests set MSW_PAIR_TARGETS, to look on this machine only.
		read -ra targets <<< "${MSW_PAIR_TARGETS:-$(msw_host_address)}"
		found=()
		msw_pair_start scan "$MSW_PAIR_PORT" "$MSW_PAIR_WAIT" "${targets[@]}"
		while msw_pair_next; do
			case $MSW_PAIR_EVENT in
				FOUND) found+=("$MSW_PAIR_ARGS") ;;
				KEY) [[ $MSW_KEY == escape || $MSW_KEY == [qQ] ]] && break ;;
				*) break ;;
			esac
		done
		msw_pair_stop
		[[ $MSW_PAIR_EVENT == KEY ]] && return 1
		(( ${#found[@]} )) && break

		msw_ui_pick "$title" "$(msw_msg "No Deck found. Both have to be on the same network.")" \
			again "$(msw_msg "Look again")" \
			code  "$(msw_msg "Show a pairing code instead")" \
			|| return 1
		if [[ $MSW_PICKED == code ]]; then
			msw_ui_host_code "$code"
			return
		fi
	done

	line="${found[0]}"
	if (( ${#found[@]} > 1 )); then
		for line in "${found[@]}"; do
			choices+=("$line" "${line#* } $(msw_dim "(${line%% *})")")
		done
		msw_ui_pick "$title" "$(msw_msg "Which Deck?")" "${choices[@]}" || return 1
		line="$MSW_PICKED"
	fi
	address="${line%% *}" name="${line#* }"

	msw_ui_screen "$title"
	printf '  %s\n' "$(msw_dim "$(msw_msg "One moment...")")"
	MSW_PAIR_CODE="$code"
	msw_pair_start send "$address" "$MSW_PAIR_PORT"
	MSW_PAIR_CODE=''

	while msw_pair_next; do
		case $MSW_PAIR_EVENT in
			KEY) [[ $MSW_KEY == escape || $MSW_KEY == [qQ] ]] && break ;;
			PEER)
				read -r digits _ <<< "$MSW_PAIR_ARGS"
				msw_ui_screen "$title"
				msw_ui_text "$(msw_msg "Found %s (%s). It shows a code too:" "$name" "$address")"
				msw_ui_digits "$digits"
				if ! msw_ui_yesno "$(msw_msg "Is it the same code?")"; then
					msw_pair_answer no
					msw_ui_bad "$(msw_msg "Not paired.")"
					break
				fi
				msw_pair_answer yes
				printf '\n  %s\n' "$(msw_dim "$(msw_msg "Now say yes on the Deck too.")")"
				;;
			OK)
				msw_ui_ok "$(msw_msg "Paired with %s. It logs this PC in when it wakes it." "$name")"
				break
				;;
			NO)
				msw_ui_bad "$(msw_msg "The Deck said no.")"
				break
				;;
			ERROR)
				msw_ui_bad "$(msw_msg "The Deck could not save it.")"
				break
				;;
			*)
				msw_ui_bad "$(msw_msg "Pairing did not work: %s" "${MSW_PAIR_ARGS:-$MSW_PAIR_EVENT}")"
				break
				;;
		esac
	done
	msw_pair_stop
	[[ $MSW_PAIR_EVENT == OK ]]
}

# msw_ui_host_code <code>
msw_ui_host_code() {
	msw_ui_screen "$(msw_msg "Pairing code")"
	msw_ui_text "$(msw_msg "On the Deck, open the menu, press 2 and then c. Then paste this line:")"
	printf '\n%s\n\n' "$1"
	msw_ui_text "$(msw_msg "It holds the secret of the login trigger. Keep it to yourself.")"
	msw_ui_pause
}

MSW_HOST_SETTINGS=()

msw_ui_host_settings() {
	MSW_HOST_SETTINGS=(
		"User|user||$(msw_msg "Logs in")|$(msw_msg "The user this PC logs in after a wake-up from the Deck.")"
		"Port|port|$MSW_DEFAULT_PORT|$(msw_msg "Port")|$(msw_msg "Where the login trigger listens. After a change, pair the Deck again.")"
		"NtfyTopic|text||$(msw_msg "Push topic")|$(msw_msg "Sends a push through ntfy once the PC is ready. Anyone who knows the topic can read along, so pick one nobody guesses. Empty turns it off.")"
		"NtfyServer|text|https://ntfy.sh|$(msw_msg "Push server")|$(msw_msg "Any ntfy server works, your own too.")"
		"Secret|secret||$(msw_msg "Secret")|$(msw_msg "Shared with the Deck when pairing. A new one turns away every Deck paired before.")"
	)
	msw_ui_settings "$MSW_HOST_CONFIG" msw_host_config_set "${MSW_HOST_SETTINGS[@]}"
}

msw_ui_host_menu() {
	msw_need_root
	MSW_IN_MENU=1
	msw_ui_begin

	while true; do
		msw_ui_screen "$MSW_PRETTY · $(msw_msg "this PC")"
		msw_ui_host_status
		printf '\n'
		msw_ui_show_msg
		printf '  [1] %s\n' "$(msw_msg "Turn the login trigger on or off")"
		printf '  [2] %s\n' "$(msw_msg "Pair with the Deck")"
		printf '  [3] %s\n' "$(msw_msg "Settings")"
		printf '  [q] %s\n' "$(msw_msg "Quit")"
		printf '\n  > '

		msw_read_key || break
		case $MSW_KEY in
			1)
				if msw_host_on; then
					msw_ui_run msw_do_host_disable
				else
					msw_ui_run msw_do_host_enable
				fi
				;;
			2) msw_ui_host_pair ;;
			3)
				# A new user or port only counts once the trigger is set up again.
				msw_ui_host_settings && msw_host_on && msw_ui_run msw_do_host_enable
				;;
			q|Q) break ;;
		esac
	done

	printf '\n'
	msw_ui_end
}
