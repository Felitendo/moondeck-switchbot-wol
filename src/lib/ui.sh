# shellcheck shell=bash
#
# The pieces the menus are made of: keys, a line editor, a pick list, a yes or
# no question.
#
# Every widget assigns its result to a variable instead of printing it, so
# none of them has to run in a subshell. That keeps the terminal state in one
# place, and a pasted line of a few hundred characters does not cost a fork
# per character.

# Terminal mode.
#
# bash flips the terminal out of canonical mode for each `read -n1` and back in
# between. In canonical mode a backspace typed in that gap is eaten by the line
# discipline, so the whole interface holds non-canonical mode instead.
#
# Begin and end nest: an action that asks something works the same from the
# command line and from inside a menu, and only the outermost end restores.
MSW_TERM_SAVED=''
MSW_UI_DEPTH=0

msw_ui_begin() {
	(( MSW_UI_DEPTH++ )) && return 0
	msw_have stty && [[ -t 0 ]] || return 0
	MSW_TERM_SAVED="$(stty -g 2>/dev/null)" || { MSW_TERM_SAVED=''; return 0; }
	stty -icanon -echo min 1 time 0 2>/dev/null
	trap 'msw_ui_restore' EXIT
	trap 'msw_ui_restore; exit 130' INT TERM
}

msw_ui_end() {
	(( MSW_UI_DEPTH > 0 && --MSW_UI_DEPTH == 0 )) && msw_ui_restore
	return 0
}

msw_ui_restore() {
	[[ -n $MSW_TERM_SAVED ]] || return 0
	stty "$MSW_TERM_SAVED" 2>/dev/null
	MSW_TERM_SAVED=''
}

MSW_CLEAR="$(clear 2>/dev/null)" || MSW_CLEAR=$'\033[H\033[2J'

# msw_ui_screen <title>
msw_ui_screen() {
	printf '%s\n%s  %s%s\n\n' "$MSW_CLEAR" "$MSW_C_BOLD$MSW_C_BLUE" "$1" "$MSW_C_RESET"
}

# msw_ui_text <text>
# A paragraph or more, wrapped to the terminal and indented like the rest.
msw_ui_text() {
	local size width line
	# stty asks standard input, which is still the terminal inside $(...).
	size="$(stty size 2>/dev/null)"
	width="${size#* }"
	[[ $width =~ ^[0-9]+$ ]] && (( width > 20 )) || width=80
	(( width > 84 )) && width=84
	while IFS= read -r line; do
		printf '  %s\n' "$line"
	done < <(printf '%s\n' "$1" | fold -s -w $(( width - 4 )))
}

# msw_read_key
# One keypress in MSW_KEY, arrows and the like by name. The tail of an escape
# sequence is read here, so it is not taken for three separate keys.
MSW_KEY=''

msw_read_key() {
	local k rest

	IFS= read -rsn1 k || return 1
	case $k in
		$'\e')
			MSW_KEY=escape
			if IFS= read -rsn2 -t 0.05 rest; then
				case $rest in
					'[A'|OA) MSW_KEY=up ;;
					'[B'|OB) MSW_KEY=down ;;
					'[C'|OC) MSW_KEY=right ;;
					'[D'|OD) MSW_KEY=left ;;
				esac
			fi
			;;
		''|$'\r')      MSW_KEY=enter ;;
		$'\x7f'|$'\b') MSW_KEY=backspace ;;
		' ')           MSW_KEY=space ;;
		*)             MSW_KEY="$k" ;;
	esac
}

msw_ui_pause() {
	printf '\n  %s' "$(msw_dim "$(msw_msg "Press any key to continue...")")"
	msw_read_key
	printf '\n'
}

# msw_ui_yesno <question>
# No is the default, and anything but y (or j) means no.
msw_ui_yesno() {
	printf '\n  %s %s ' "$1" "$(msw_msg "[y/N]")"
	msw_read_key || return 1
	printf '\n'
	[[ $MSW_KEY == [yYjJ] ]]
}

# msw_ui_line <label> [initial] [secret]
# A line of input in MSW_LINE. Returns 1 on Esc.
#
# A secret is shown as dots and a count. Silent input looked as if a paste had
# not arrived at all, and the count tells a whole token from half of one.
MSW_LINE=''

msw_ui_line() {
	local label="$1" buf="${2:-}" secret="${3:-}" shown n count fmt

	# Looked up once: a paste arrives one key at a time, and a fork per key
	# would make a long code crawl in.
	msw_msg_into "%d characters"
	fmt="$MSW_MSG_RESULT"

	MSW_LINE=''
	printf '\n  %s\n' "$label"
	while true; do
		n=${#buf}
		if [[ -n $secret ]]; then
			printf -v shown '%*s' $(( n < 24 ? n : 24 )) ''
			shown="${shown// /•}"
			if (( n )); then
				# shellcheck disable=SC2059  # the format is the translated message
				printf -v count "$fmt" "$n"
				shown+=" $MSW_C_DIM$count$MSW_C_RESET"
			fi
		elif (( n > 60 )); then
			shown="…${buf: -59}"
		else
			shown="$buf"
		fi
		printf '\r\033[K  > %s' "$shown"

		msw_read_key || { printf '\n'; return 1; }
		case $MSW_KEY in
			enter)     printf '\n'; MSW_LINE="$buf"; return 0 ;;
			escape)    printf '\n'; return 1 ;;
			backspace) buf="${buf%?}" ;;
			space)     buf+=' ' ;;
			up|down|left|right) ;;
			*) [[ ${#MSW_KEY} -eq 1 ]] && buf+="$MSW_KEY" ;;
		esac
	done
}

# msw_ui_pick <title> <text> <tag> <label> [<tag> <label>...]
# A list to pick one from, the tag of the picked one in MSW_PICKED. Returns 1
# on Esc.
MSW_PICKED=''

msw_ui_pick() {
	local title="$1" text="$2" hint head frame i count cursor=0 marker
	local selected="${MSW_C_BLUE}▸${MSW_C_RESET} "
	local -a tags=() labels=()
	shift 2

	while (( $# >= 2 )); do
		tags+=("$1")
		labels+=("$2")
		shift 2
	done
	count=${#tags[@]}
	(( count )) || return 1
	MSW_PICKED=''

	msw_msg_into "Up/Down: select, Enter: choose, Esc: back"
	hint="$MSW_MSG_RESULT"
	head="$(msw_ui_screen "$title"; [[ -n $text ]] && msw_ui_text "$text")"$'\n\n'

	while true; do
		frame="$head"
		for (( i = 0; i < count; i++ )); do
			if (( i == cursor )); then marker="$selected"; else marker='  '; fi
			frame+="  ${marker}${labels[i]}"$'\n'
		done
		frame+=$'\n'"  ${MSW_C_DIM}${hint}${MSW_C_RESET}"$'\n'
		printf '%s' "$frame"

		msw_read_key || return 1
		case $MSW_KEY in
			up|k)   cursor=$(( (cursor - 1 + count) % count )) ;;
			down|j) cursor=$(( (cursor + 1) % count )) ;;
			enter|space|right)
				MSW_PICKED="${tags[cursor]}"
				return 0
				;;
			escape|left|q|Q) return 1 ;;
		esac
	done
}

# What the last action printed. The menus show it under their status until
# the next key, so nothing waits for a key on a screen of its own.
MSW_UI_MSG=''

# Set while a menu runs, so actions can leave out hints the menu already shows.
MSW_IN_MENU=''

# msw_ui_run <command...>
# Runs an action in this shell, with its output kept for the menu. Several in a
# row add up.
msw_ui_run() {
	local tmp

	printf '  %s\n' "$(msw_dim "$(msw_msg "One moment...")")"
	tmp="$(mktemp)" || { "$@"; return; }
	"$@" > "$tmp" 2>&1
	MSW_UI_MSG+="${MSW_UI_MSG:+$'\n'}$(< "$tmp")"
	rm -f -- "$tmp"
}

# msw_ui_show_msg
msw_ui_show_msg() {
	local line
	[[ -n $MSW_UI_MSG ]] || return 0
	while IFS= read -r line; do
		printf '  %s\n' "$line"
	done <<< "$MSW_UI_MSG"
	printf '\n'
	MSW_UI_MSG=''
}
