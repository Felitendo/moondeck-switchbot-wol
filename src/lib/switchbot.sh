# shellcheck shell=bash
#
# Talking to the SwitchBot cloud, through switchbot.py.
#
# A Bot is Bluetooth only. The cloud reaches it through a SwitchBot hub, and
# only once "Cloud Services" is on for it in the app.

MSW_SB_ERROR=''
MSW_SB_DEVICES=''

# _msw_sb_run <token> <secret> <switchbot.py args...>
# Output in MSW_SB_OUT. On failure MSW_SB_ERROR says why, translated.
_msw_sb_run() {
	local token="$1" secret="$2" rc
	shift 2

	MSW_SB_ERROR=''
	MSW_SB_OUT="$(MSW_SB_TOKEN="$token" MSW_SB_SECRET="$secret" msw_python switchbot "$@")"
	rc=$?

	case $rc in
		0) return 0 ;;
		2) MSW_SB_ERROR="$(msw_msg "Could not reach the SwitchBot API: %s" "$MSW_SB_OUT")" ;;
		3) MSW_SB_ERROR="$(msw_msg "The SwitchBot API said no: %s (status %s)" \
			"${MSW_SB_OUT#*$'\t'}" "${MSW_SB_OUT%%$'\t'*}")" ;;
		*) MSW_SB_ERROR="$(msw_msg "The SwitchBot helper failed.")" ;;
	esac
	return 1
}

# msw_sb_devices <token> <secret>
# Lines of "id<TAB>name<TAB>type" in MSW_SB_DEVICES, Bots first.
msw_sb_devices() {
	_msw_sb_run "$1" "$2" devices || return 1
	MSW_SB_DEVICES="$MSW_SB_OUT"
}

# msw_sb_command <token> <secret> <device> <command>
msw_sb_command() {
	_msw_sb_run "$1" "$2" command "$3" "$4"
}

# msw_sb_command_label <command>
msw_sb_command_label() {
	case $1 in
		turnOn) msw_msg "switch on" ;;
		*)      msw_msg "press" ;;
	esac
}
