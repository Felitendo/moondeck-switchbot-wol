# shellcheck shell=bash
#
# Names, paths, translations, output helpers and the log.
#
# The same program runs on both ends. On the Steam Deck it lives in the user's
# home and never needs root. On the PC that gets woken, only the `host`
# commands run, and those need root because they set up a system service.

MSW_VERSION="@VERSION@"
MSW_NAME="moondeck-switchbot-wol"
MSW_PRETTY="MoonDeck SwitchBot"

MSW_LIBDIR="${MSW_LIBDIR:-@LIBDIR@}"
MSW_LIBEXECDIR="${MSW_LIBEXECDIR:-@LIBEXECDIR@}"
MSW_LOCALEDIR="${MSW_LOCALEDIR:-@LOCALEDIR@}"

# MoonDeck's plugin backend starts the wake-up with an environment of its own,
# so HOME is looked up rather than trusted to be there.
: "${HOME:=$(getent passwd "$(id -u)" | cut -d: -f6)}"

# Deck side: everything in the user's home. The config holds API credentials,
# so it is created private.
MSW_CONFIG="${MSW_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/$MSW_NAME/config}"
MSW_STATEDIR="${MSW_STATEDIR:-${XDG_STATE_HOME:-$HOME/.local/state}/$MSW_NAME}"
MSW_LOG="$MSW_STATEDIR/log"

# MoonDeck keeps its settings here, see moondeck.sh.
MSW_MOONDECK_SETTINGS="${MSW_MOONDECK_SETTINGS:-${XDG_CONFIG_HOME:-$HOME/.config}/moondeck/settings.json}"

# Host side. The secret is a file of its own, so the config can be shown and
# changed without ever printing it.
MSW_HOST_CONFDIR="${MSW_HOST_CONFDIR:-/etc/$MSW_NAME}"
MSW_HOST_CONFIG="$MSW_HOST_CONFDIR/host.conf"
MSW_HOST_SECRET="$MSW_HOST_CONFDIR/secret"
MSW_HOST_STATEDIR="${MSW_HOST_STATEDIR:-/var/lib/$MSW_NAME}"
MSW_UNITDIR="${MSW_UNITDIR:-/etc/systemd/system}"

MSW_DEFAULT_PORT=58471

# Set by the tests and by scripts/sandbox.sh: the host side prints the
# commands that would change the system instead of running them.
MSW_DRY_RUN="${MSW_DRY_RUN:-}"

# ---------------------------------------------------------------------------
# Translations
# ---------------------------------------------------------------------------

export TEXTDOMAIN="$MSW_NAME"
export TEXTDOMAINDIR="$MSW_LOCALEDIR"

msw_ui_locale() {
	local l="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" f

	# Under sudo or from MoonDeck the locale can be missing entirely.
	if [[ -z $l ]]; then
		for f in /etc/locale.conf /etc/default/locale; do
			[[ -r $f ]] || continue
			l="$(sed -n 's/^LANG=//p' "$f" | tr -d '"' | head -n1)"
			[[ -n $l ]] && break
		done
	fi
	printf '%s\n' "${l:-C}"
}

MSW_LOCALE="$(msw_ui_locale)"

# Every gettext lookup is a fork and the menus redraw a screenful of labels
# per key, so results are memoized.
declare -A MSW_MSG_CACHE=()
MSW_MSG_RESULT=''

# msw_msg_into <msgid>
# Plain lookup with the result in MSW_MSG_RESULT, no fork and no formatting.
msw_msg_into() {
	local msgid="$1"

	if [[ -n ${MSW_MSG_CACHE[$msgid]+set} ]]; then
		MSW_MSG_RESULT="${MSW_MSG_CACHE[$msgid]}"
		return 0
	fi

	MSW_MSG_RESULT="$(LC_ALL="$MSW_LOCALE" LANGUAGE="${MSW_LOCALE%%.*}" gettext -- "$msgid" 2>/dev/null)"
	[[ -n $MSW_MSG_RESULT ]] || MSW_MSG_RESULT="$msgid"
	MSW_MSG_CACHE[$msgid]="$MSW_MSG_RESULT"
}

# msw_msg <msgid> [printf args...]
msw_msg() {
	local msgid="$1"
	shift
	msw_msg_into "$msgid"

	# Without arguments the message is text, not a format: a literal percent
	# sign in a translation must not turn into a conversion.
	if (( $# == 0 )); then
		printf '%s' "$MSW_MSG_RESULT"
		return
	fi
	# shellcheck disable=SC2059  # the format string is the translated message
	printf -- "$MSW_MSG_RESULT" "$@"
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

# Decided once, while stdout is still what the process was started with.
MSW_INTERACTIVE=''
[[ -t 1 ]] && MSW_INTERACTIVE=1

if [[ -n $MSW_INTERACTIVE && -z ${NO_COLOR:-} ]]; then
	MSW_C_RESET=$'\033[0m'
	MSW_C_BOLD=$'\033[1m'
	MSW_C_DIM=$'\033[2m'
	MSW_C_BLUE=$'\033[38;2;23;147;209m'
	MSW_C_GREEN=$'\033[32m'
	MSW_C_YELLOW=$'\033[33m'
	MSW_C_RED=$'\033[31m'
else
	MSW_C_RESET='' MSW_C_BOLD='' MSW_C_DIM='' MSW_C_BLUE=''
	MSW_C_GREEN='' MSW_C_YELLOW='' MSW_C_RED=''
fi

msw_say()  { printf '%s\n' "$*"; }
msw_head() { printf '\n%s%s%s\n\n' "$MSW_C_BOLD$MSW_C_BLUE" "$*" "$MSW_C_RESET"; }
msw_ok()   { printf '%s✔%s %s\n' "$MSW_C_GREEN" "$MSW_C_RESET" "$*"; }
msw_bad()  { printf '%s✘%s %s\n' "$MSW_C_RED" "$MSW_C_RESET" "$*" >&2; }
msw_note() { printf '%s•%s %s\n' "$MSW_C_DIM" "$MSW_C_RESET" "$*"; }

msw_have() { command -v "$1" > /dev/null 2>&1; }

# msw_row <label> <value>
# printf pads by bytes, so a label with an umlaut would come out short.
# ${#s} counts characters, so the padding is worked out here.
msw_row() {
	local label="$1" value="$2" pad
	pad=$(( 24 - ${#label} ))
	(( pad < 0 )) && pad=0
	printf '  %s%*s %s\n' "$label" "$pad" '' "$value"
}

msw_onoff() {
	if [[ $1 == yes ]]; then
		printf '%s%s%s' "$MSW_C_GREEN" "$(msw_msg "ON")" "$MSW_C_RESET"
	else
		printf '%s%s%s' "$MSW_C_DIM" "$(msw_msg "OFF")" "$MSW_C_RESET"
	fi
}

msw_dim()  { printf '%s%s%s' "$MSW_C_DIM" "$*" "$MSW_C_RESET"; }
msw_warn() { printf '%s%s%s' "$MSW_C_YELLOW" "$*" "$MSW_C_RESET"; }

# msw_time_ago <unix time>
# One msw_msg per line: xgettext only finds a call at the start of a line, not
# after `then` or `{`.
msw_time_ago() {
	local ts="$1" delta

	if [[ ! $ts =~ ^[0-9]+$ ]]; then
		msw_msg "never"
		return
	fi
	delta=$(( $(date +%s) - ts ))
	(( delta < 0 )) && delta=0

	if (( delta < 60 )); then
		msw_msg "just now"
	elif (( delta < 120 )); then
		msw_msg "1 minute ago"
	elif (( delta < 3600 )); then
		msw_msg "%d minutes ago" "$(( delta / 60 ))"
	elif (( delta < 7200 )); then
		msw_msg "1 hour ago"
	elif (( delta < 86400 )); then
		msw_msg "%d hours ago" "$(( delta / 3600 ))"
	elif (( delta < 172800 )); then
		msw_msg "1 day ago"
	else
		msw_msg "%d days ago" "$(( delta / 86400 ))"
	fi
}

# ---------------------------------------------------------------------------
# State and the log
# ---------------------------------------------------------------------------

msw_state_read() {
	[[ -r $MSW_STATEDIR/$1 ]] && cat -- "$MSW_STATEDIR/$1"
	return 0
}

msw_state_write() {
	mkdir -p "$MSW_STATEDIR" 2>/dev/null || return 1
	printf '%s\n' "$2" > "$MSW_STATEDIR/$1"
}

# msw_log <line>
# For the wake-up. MoonDeck keeps what is printed in its own log, and the log
# file keeps it for `log`.
msw_log() {
	local line
	line="$(date '+%Y-%m-%d %H:%M:%S') $*"
	printf '%s\n' "$line"
	mkdir -p "$MSW_STATEDIR" 2>/dev/null && printf '%s\n' "$line" >> "$MSW_LOG"
	return 0
}

# The log only ever grows by a few lines per wake-up, so it is cut back now and
# then rather than rotated.
msw_log_trim() {
	local tmp
	[[ -f $MSW_LOG ]] || return 0
	(( $(wc -l < "$MSW_LOG") > 2000 )) || return 0
	tmp="$(mktemp "$MSW_LOG.XXXXXX")" || return 0
	tail -n 1000 "$MSW_LOG" > "$tmp" && mv -f "$tmp" "$MSW_LOG"
	rm -f "$tmp"
}

# msw_python <helper> [args...]
# The small Python helpers next to the shell libraries.
msw_python() {
	local helper="$1"
	shift
	python3 "$MSW_LIBDIR/$helper.py" "$@"
}
