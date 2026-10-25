# shellcheck shell=bash
#
# The PC that gets woken: the login trigger.
#
# Pressing the power button gets the PC as far as its login screen. Sunshine
# only starts with a session, so somebody has to log in, and plain autologin
# would let anybody who switches the PC on into the desktop. So the Deck proves
# that it did the waking, and only then the PC logs in, once. See login-agent.
#
# The units come with the package. `host enable` switches them on, writes the
# port when it is not the default one, and opens the firewall for the network
# the PC is in.

MSW_SOCKET="moondeck-switchbot-wol-login.socket"
MSW_DISARM="moondeck-switchbot-wol-disarm.service"
MSW_PORT_DROPIN="$MSW_UNITDIR/$MSW_SOCKET.d/port.conf"
MSW_UFW_COMMENT="$MSW_NAME"
MSW_AGENT="$MSW_LIBEXECDIR/login-agent"

# msw_run <command...>
# Runs it, or only says what it would run in a dry run.
msw_run() {
	if [[ -n $MSW_DRY_RUN ]]; then
		printf 'dry run: %s\n' "$*" >&2
		return 0
	fi
	"$@"
}

# msw_need_root
# Starts this again through sudo when somebody is at the terminal, so that
# `moondeck-switchbot-wol host` just works instead of printing a lecture.
msw_need_root() {
	local c

	[[ $EUID -eq 0 || -n $MSW_DRY_RUN ]] && return 0
	if [[ -t 0 && -t 1 ]]; then
		for c in sudo run0 doas; do
			msw_have "$c" && exec "$c" "$MSW_SELF" "${MSW_ARGV[@]}"
		done
	fi
	msw_bad "$(msw_msg "This has to run as root.")"
	exit 2
}

# The user who asked, when sudo or doas says so, or else whoever is logged in.
msw_guess_user() {
	local user="${SUDO_USER:-${DOAS_USER:-}}"

	if [[ -z $user || $user == root ]] && msw_have loginctl; then
		user="$(loginctl list-sessions --no-legend 2>/dev/null \
			| awk '$3 != "" && $3 != "root" { print $3; exit }')"
	fi
	[[ $user == root ]] && user=''
	printf '%s\n' "$user"
}

# Everybody who could log in at the login screen.
msw_login_users() {
	getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ { print $1 }'
}

msw_display_manager() {
	local path
	path="$("$MSW_AGENT" --check 2>/dev/null)" || return 1
	case $path in
		*plasmalogin*) printf 'Plasma Login\n' ;;
		*sddm*)        printf 'SDDM\n' ;;
		*)             printf '%s\n' "$path" ;;
	esac
}

msw_host_on() {
	if [[ -n $MSW_DRY_RUN ]]; then
		[[ $HCFG_ENABLED == yes ]]
	else
		systemctl is-active --quiet "$MSW_SOCKET" 2>/dev/null
	fi
}

# ---------------------------------------------------------------------------
# The secret
# ---------------------------------------------------------------------------

# 128 bits are plenty for an HMAC key and keep the pairing code short.
msw_host_secret_new() {
	local secret
	secret="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
	[[ ${#secret} -eq 32 ]] || return 1
	mkdir -p "$MSW_HOST_CONFDIR" || return 1
	( umask 077; printf '%s\n' "$secret" > "$MSW_HOST_SECRET" )
}

# msw_host_secret
# Prints the secret, and makes one when there is none yet. Kept across disable
# and enable, so a Deck that is paired stays paired.
msw_host_secret() {
	[[ -s $MSW_HOST_SECRET ]] || msw_host_secret_new || return 1
	tr -d '\n' < "$MSW_HOST_SECRET"
}

# ---------------------------------------------------------------------------
# The firewall
# ---------------------------------------------------------------------------

msw_ufw_active() {
	msw_have ufw && ufw status 2>/dev/null | grep -qi '^Status: active'
}

# This PC's address with its prefix, for example 192.168.2.10/24. Containers
# and VPNs bring addresses of their own, so those are skipped.
msw_host_address() {
	ip -4 -o addr show scope global 2>/dev/null \
		| awk '$2 !~ /^(docker|virbr|br-|veth|tailscale|wg|tun)/ { print $4; exit }'
}

# The network of it, for example 192.168.2.0/24.
msw_host_subnet() {
	local cidr
	cidr="$(msw_host_address)"
	[[ -n $cidr ]] || return 1
	python3 -c 'import ipaddress, sys; print(ipaddress.ip_network(sys.argv[1], strict=False))' "$cidr"
}

# Where the open port lets connections in from, empty when it is not open.
msw_ufw_source() {
	msw_ufw_active || return 0
	ufw status 2>/dev/null | awk -v c="# $MSW_UFW_COMMENT" 'index($0, c) { print $3; exit }'
}

msw_ufw_close() {
	local number
	msw_have ufw || return 0
	# Highest first, because deleting a rule renumbers the ones after it.
	while read -r number; do
		msw_run ufw --force delete "$number" > /dev/null 2>&1
	done < <(ufw status numbered 2>/dev/null | grep -F "# $MSW_UFW_COMMENT" \
		| sed -n 's/^\[ *\([0-9]\+\)\].*/\1/p' | sort -rn)
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

msw_do_host_enable() {
	local subnet

	msw_need_root
	msw_host_config_load

	if ! msw_display_manager > /dev/null; then
		msw_bad "$(msw_msg "This display manager is not supported. Plasma Login and SDDM are.")"
		return 1
	fi
	if [[ -z $HCFG_USER ]]; then
		HCFG_USER="$(msw_guess_user)"
		if [[ -z $HCFG_USER ]]; then
			msw_bad "$(msw_msg "Which user should be logged in? Set it under Settings first.")"
			return 1
		fi
		msw_host_config_set User "$HCFG_USER"
	fi
	if ! msw_host_secret > /dev/null; then
		msw_bad "$(msw_msg "Could not write %s." "$MSW_HOST_SECRET")"
		return 1
	fi

	# The socket listens on the default port unless told otherwise here.
	if [[ $HCFG_PORT == "$MSW_DEFAULT_PORT" ]]; then
		rm -f "$MSW_PORT_DROPIN"
		rmdir "${MSW_PORT_DROPIN%/*}" 2>/dev/null
	else
		mkdir -p "${MSW_PORT_DROPIN%/*}" \
			&& printf '[Socket]\nListenStream=\nListenStream=%s\n' "$HCFG_PORT" > "$MSW_PORT_DROPIN"
	fi

	msw_run systemctl daemon-reload
	# A restart rather than a start, so a changed port takes effect.
	if ! { msw_run systemctl enable "$MSW_SOCKET" "$MSW_DISARM" > /dev/null 2>&1 \
		&& msw_run systemctl restart "$MSW_SOCKET"; }; then
		msw_bad "$(msw_msg "Could not start %s." "$MSW_SOCKET")"
		return 1
	fi
	msw_host_config_set Enabled yes

	if msw_ufw_active && subnet="$(msw_host_subnet)"; then
		msw_ufw_close
		if msw_run ufw allow from "$subnet" to any port "$HCFG_PORT" proto tcp \
			comment "$MSW_UFW_COMMENT" > /dev/null; then
			msw_ok "$(msw_msg "Opened port %s in ufw, for %s only." "$HCFG_PORT" "$subnet")"
		fi
	fi

	msw_ok "$(msw_msg "The login trigger is on. A wake-up from the Deck logs %s in." "$HCFG_USER")"
	[[ -n ${MSW_IN_MENU:-} ]] \
		|| msw_note "$(msw_msg "Next, pair the Deck: sudo %s host pair" "$MSW_NAME")"
}

msw_do_host_disable() {
	msw_need_root
	msw_host_config_load

	# Takes a login that is still under way back out first.
	[[ -x $MSW_AGENT ]] && msw_run "$MSW_AGENT" --disarm
	msw_run systemctl disable --now "$MSW_SOCKET" "$MSW_DISARM" > /dev/null 2>&1
	msw_ufw_close
	if [[ -e $MSW_PORT_DROPIN ]]; then
		rm -f "$MSW_PORT_DROPIN"
		rmdir "${MSW_PORT_DROPIN%/*}" 2>/dev/null
		msw_run systemctl daemon-reload
	fi
	msw_host_config_set Enabled no

	msw_ok "$(msw_msg "The login trigger is off. The PC asks for the password again, however it is switched on.")"
}

# msw_host_code_pairs
# The pairs that go into the code, in MSW_HOST_PAIRS.
msw_host_code_pairs() {
	local secret
	secret="$(msw_host_secret)" || return 1
	MSW_HOST_PAIRS=("TriggerPort=$HCFG_PORT" "TriggerSecret=$secret")
}

# msw_do_host_code [--new]
# The code on stdout, so it can be piped. The menu has a screen of its own.
msw_do_host_code() {
	local arg

	msw_need_root
	msw_host_config_load

	for arg in "$@"; do
		case $arg in
			--new)
				msw_host_secret_new || { msw_bad "$(msw_msg "Could not write %s." "$MSW_HOST_SECRET")"; return 1; }
				msw_note "$(msw_msg "New secret made. A Deck that was paired before has to be paired again.")" >&2
				;;
			*) msw_bad "$(msw_msg "Unknown option: %s" "$arg")"; return 1 ;;
		esac
	done

	msw_host_code_pairs || { msw_bad "$(msw_msg "Could not write %s." "$MSW_HOST_SECRET")"; return 1; }
	[[ $HCFG_ENABLED == yes ]] \
		|| msw_note "$(msw_msg "The login trigger is off. Turn it on with: sudo %s host enable" "$MSW_NAME")" >&2
	msw_pair_encode "${MSW_HOST_PAIRS[@]}"
}

msw_do_host_pair() {
	local rc

	msw_need_root
	if [[ ! -t 0 || ! -t 1 ]]; then
		msw_bad "$(msw_msg "This asks questions, so it needs a terminal.")"
		return 1
	fi
	msw_ui_begin
	msw_ui_host_pair
	rc=$?
	msw_ui_end
	printf '%s' "$MSW_CLEAR"
	[[ -n $MSW_UI_MSG ]] && printf '%s\n' "$MSW_UI_MSG"
	return "$rc"
}

# The last login trigger, as the agent wrote it down.
msw_host_last() {
	local when result
	if [[ ! -r $MSW_HOST_STATEDIR/last ]]; then
		msw_msg "never"
		return
	fi
	IFS=$'\t' read -r when result < "$MSW_HOST_STATEDIR/last"
	case $result in
		login)   msw_msg "%s, logged in" "$(msw_time_ago "$when")" ;;
		already) msw_msg "%s, was logged in already" "$(msw_time_ago "$when")" ;;
		failed)  msw_warn "$(msw_msg "%s, logging in did not work" "$(msw_time_ago "$when")")" ;;
		denied)  msw_warn "$(msw_msg "%s, turned away a Deck with the wrong secret" "$(msw_time_ago "$when")")" ;;
		*)       msw_time_ago "$when" ;;
	esac
}

msw_ui_host_status() {
	local dm source

	msw_host_config_load
	if msw_host_on; then
		msw_row "$(msw_msg "Login trigger")" "$(msw_onoff yes)"
	else
		msw_row "$(msw_msg "Login trigger")" "$(msw_onoff no)"
	fi
	printf '\n'

	if [[ -n $HCFG_USER ]]; then
		msw_row "$(msw_msg "Logs in")" "$HCFG_USER"
	else
		msw_row "$(msw_msg "Logs in")" "$(msw_warn "$(msw_msg "nobody yet")")"
	fi

	if dm="$(msw_display_manager)"; then
		msw_row "$(msw_msg "Display manager")" "$dm"
	else
		msw_row "$(msw_msg "Display manager")" \
			"$MSW_C_RED$(msw_msg "not supported (Plasma Login and SDDM are)")$MSW_C_RESET"
	fi

	source="$(msw_ufw_source)"
	if [[ -n $source ]]; then
		msw_row "$(msw_msg "Port")" "$HCFG_PORT $(msw_dim "$(msw_msg "(open in ufw for %s)" "$source")")"
	else
		msw_row "$(msw_msg "Port")" "$HCFG_PORT"
	fi

	if [[ -n $HCFG_NTFY_TOPIC ]]; then
		msw_row "$(msw_msg "Push when ready")" "$HCFG_NTFY_TOPIC $(msw_dim "($HCFG_NTFY_SERVER)")"
	else
		msw_row "$(msw_msg "Push when ready")" "$(msw_onoff no)"
	fi

	msw_row "$(msw_msg "Last wake-up")" "$(msw_host_last)"
}

msw_do_host_status() {
	msw_need_root
	msw_head "  $MSW_PRETTY · $(msw_msg "this PC")"
	msw_ui_host_status
	printf '\n'
}
