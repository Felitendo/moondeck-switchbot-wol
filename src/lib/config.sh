# shellcheck shell=bash
#
# Reading and writing the two config files: the Deck's in the user's home, and
# the host's in /etc.
#
# Both are written by the program and every option in them is reachable from
# the menu. They are parsed rather than sourced: one "Key=Value" per line,
# '#' starts a comment line. A value is everything after the first '=', so a
# secret may contain any character but a newline.

MSW_CONF_VALUE=''

# msw_conf_get <file> <Key> [default]
# Result in MSW_CONF_VALUE. Assigning rather than printing keeps the settings
# screen from forking for every row it draws.
msw_conf_get() {
	local file="$1" key="$2" line

	MSW_CONF_VALUE="${3:-}"
	[[ -r $file ]] || return 0
	while IFS= read -r line; do
		[[ $line == "$key="* ]] && MSW_CONF_VALUE="${line#*=}"
	done < "$file"
	[[ -n $MSW_CONF_VALUE ]] || MSW_CONF_VALUE="${3:-}"
	return 0
}

# msw_conf_set <file> <Key> <Value> [header]
# The header is written when the file is created. A new file is private: the
# Deck's holds the API credentials, and only root reads the host's.
msw_conf_set() {
	local file="$1" key="$2" value="$3" header="${4:-}" tmp

	if [[ ! -e $file ]]; then
		mkdir -p "$(dirname "$file")" || return 1
		( umask 077; printf '%s' "$header" > "$file" ) || return 1
	fi

	tmp="$(mktemp "$file.XXXXXX")" || return 1
	chmod --reference="$file" "$tmp" 2>/dev/null
	if awk -v key="$key" -v value="$value" '
		index($0, key "=") == 1 { if (!done) print key "=" value; done = 1; next }
		{ print }
		END { if (!done) print key "=" value }
	' "$file" > "$tmp" && mv -f "$tmp" "$file"; then
		return 0
	fi
	rm -f "$tmp"
	return 1
}

# msw_conf_del <file> <Key>
msw_conf_del() {
	local file="$1" key="$2" tmp

	[[ -f $file ]] || return 0
	tmp="$(mktemp "$file.XXXXXX")" || return 1
	chmod --reference="$file" "$tmp" 2>/dev/null
	if awk -v key="$key" 'index($0, key "=") != 1' "$file" > "$tmp" && mv -f "$tmp" "$file"; then
		return 0
	fi
	rm -f "$tmp"
	return 1
}

# ---------------------------------------------------------------------------
# The Deck
# ---------------------------------------------------------------------------

MSW_CONFIG_HEADER="# $MSW_PRETTY
#
# Written by \`$MSW_NAME\`. It holds your SwitchBot credentials, keep it
# private. Nothing here needs editing by hand.
"

msw_config_set() { msw_conf_set "$MSW_CONFIG" "$1" "$2" "$MSW_CONFIG_HEADER"; }
msw_config_del() { msw_conf_del "$MSW_CONFIG" "$1"; }

msw_config_load() {
	local f="$MSW_CONFIG"

	msw_conf_get "$f" Token;      CFG_TOKEN="$MSW_CONF_VALUE"
	msw_conf_get "$f" Secret;     CFG_SECRET="$MSW_CONF_VALUE"
	msw_conf_get "$f" Device;     CFG_DEVICE="$MSW_CONF_VALUE"
	msw_conf_get "$f" DeviceName; CFG_DEVICE_NAME="$MSW_CONF_VALUE"
	msw_conf_get "$f" Command press; CFG_COMMAND="$MSW_CONF_VALUE"

	# Pressing a power button twice turns the PC off again, so a second press
	# within this many seconds is refused.
	msw_conf_get "$f" Cooldown 180; CFG_COOLDOWN="$MSW_CONF_VALUE"
	[[ $CFG_COOLDOWN =~ ^[0-9]+$ ]] || CFG_COOLDOWN=180

	# The login trigger, from the pairing code.
	msw_conf_get "$f" TriggerPort "$MSW_DEFAULT_PORT"; CFG_TRIGGER_PORT="$MSW_CONF_VALUE"
	msw_conf_get "$f" TriggerSecret;                   CFG_TRIGGER_SECRET="$MSW_CONF_VALUE"

	# How long to keep knocking while the PC boots.
	msw_conf_get "$f" KnockTimeout 240; CFG_KNOCK_TIMEOUT="$MSW_CONF_VALUE"
	[[ $CFG_KNOCK_TIMEOUT =~ ^[0-9]+$ ]] || CFG_KNOCK_TIMEOUT=240
}

msw_switchbot_ready() {
	[[ -n $CFG_TOKEN && -n $CFG_SECRET && -n $CFG_DEVICE ]]
}

# ---------------------------------------------------------------------------
# The host
# ---------------------------------------------------------------------------

MSW_HOST_CONFIG_HEADER="# $MSW_PRETTY, the PC that gets woken
#
# Written by \`sudo $MSW_NAME host\`. Nothing here needs editing by hand.
"

msw_host_config_set() { msw_conf_set "$MSW_HOST_CONFIG" "$1" "$2" "$MSW_HOST_CONFIG_HEADER"; }

msw_host_config_load() {
	local f="$MSW_HOST_CONFIG"

	msw_conf_get "$f" Enabled no;                HCFG_ENABLED="$MSW_CONF_VALUE"
	msw_conf_get "$f" User;                      HCFG_USER="$MSW_CONF_VALUE"
	msw_conf_get "$f" Port "$MSW_DEFAULT_PORT";  HCFG_PORT="$MSW_CONF_VALUE"
	msw_conf_get "$f" NtfyTopic;                 HCFG_NTFY_TOPIC="$MSW_CONF_VALUE"
	msw_conf_get "$f" NtfyServer https://ntfy.sh; HCFG_NTFY_SERVER="$MSW_CONF_VALUE"
}
