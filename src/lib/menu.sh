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

msw_ui_pair() {
	msw_ui_screen "$(msw_msg "Pair with the PC")"
	msw_ui_text "$(msw_msg "On the PC, run this and press 2:")"
	printf '\n    %s\n\n' "$MSW_C_BOLD$MSW_NAME host$MSW_C_RESET"
	msw_ui_text "$(msw_msg "Copy the line that starts with msw1: and paste it here. In Konsole, paste with Ctrl+Shift+V.")"
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
		msw_ui_pick "$title" "$(msw_msg "First the SwitchBot. A pairing code from the PC carries all of it, so nothing has to be typed here.")" \
			pair  "$(msw_msg "Paste a pairing code from the PC")" \
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

msw_ui_host_code() {
	local code

	msw_host_config_load
	msw_host_code_pairs || { MSW_UI_MSG="$(msw_bad "$(msw_msg "Could not write %s." "$MSW_HOST_SECRET")" 2>&1)"; return 1; }

	msw_ui_screen "$(msw_msg "Pairing code")"
	msw_ui_text "$(msw_msg "The code can carry the SwitchBot setup too. Then nothing has to be typed on the Deck. The credentials are not kept on this PC, they only go into the code.")"
	if msw_ui_yesno "$(msw_msg "Put the SwitchBot setup into the code?")"; then
		msw_ui_switchbot "$(msw_msg "They are not kept on this PC. They only go into the code.")" || return 1
		MSW_HOST_PAIRS+=("Token=$SB_TOKEN" "Secret=$SB_SECRET" "Device=$SB_DEVICE"
			"DeviceName=$SB_DEVICE_NAME" "Command=$SB_COMMAND")
	fi
	code="$(msw_pair_encode "${MSW_HOST_PAIRS[@]}")"

	msw_ui_screen "$(msw_msg "Pairing code")"
	msw_ui_text "$(msw_msg "On the Deck, run %s and press 2. Then paste this line:" "$MSW_NAME")"
	printf '\n%s\n\n' "$code"
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
		"Secret|secret||$(msw_msg "Secret")|$(msw_msg "Shared with the Deck through the pairing code. A new one turns away every Deck paired before.")"
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
		printf '  [2] %s\n' "$(msw_msg "Pairing code for the Deck")"
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
			2) msw_ui_host_code ;;
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
