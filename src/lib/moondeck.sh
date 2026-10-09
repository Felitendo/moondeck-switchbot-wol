# shellcheck shell=bash
#
# MoonDeck, the Decky plugin that does the waking.
#
# MoonDeck can run an executable instead of sending a magic packet, set per
# host. `enable` turns that on for MoonDeck's current host, points it at the
# wake shim and records what was there before, so `disable` can put it back.
# The JSON itself is moondeck.py's business.

# What MoonDeck runs. It hands over to `wake` with MoonDeck's four arguments.
MSW_WAKE_SHIM="$MSW_LIBEXECDIR/wake"

# MoonDeck's WOL timeout is raised to at least this. Its default of a minute is
# made for waking from sleep, a cold boot with a login takes longer.
MSW_MOONDECK_TIMEOUT=180

# One line per host that was changed: its id and what moondeck.py changed.
MSW_MOONDECK_LEDGER="$MSW_STATEDIR/moondeck"

# msw_moondeck_load
# MoonDeck's current host in MD_ID, MD_NAME and MD_ADDRESS, and MD_OURS=yes when
# it already runs the shim. MD_STATE says what was found: ok, nohost (MoonDeck
# has no host yet) or missing (no MoonDeck). Returns 0 only for ok.
msw_moondeck_load() {
	local out id name address current custom path

	MD_ID='' MD_NAME='' MD_ADDRESS='' MD_OURS=no MD_STATE=missing
	out="$(msw_python moondeck "$MSW_MOONDECK_SETTINGS" hosts 2>/dev/null)" || return 1

	MD_STATE=nohost
	while IFS=$'\x1f' read -r id name address current custom path; do
		[[ $current == 1 ]] || continue
		MD_ID="$id" MD_NAME="$name" MD_ADDRESS="$address" MD_STATE=ok
		[[ $custom == 1 && $path == "$MSW_WAKE_SHIM" ]] && MD_OURS=yes
	done <<< "$out"
	[[ $MD_STATE == ok ]]
}

msw_moondeck_point() {
	local change

	change="$(msw_python moondeck "$MSW_MOONDECK_SETTINGS" point \
		"$MD_ID" "$MSW_WAKE_SHIM" "$MSW_MOONDECK_TIMEOUT")" || return 1

	# Only the first record of a host holds the values from before this
	# program touched it, so a second enable does not replace it.
	mkdir -p "$MSW_STATEDIR" || return 1
	grep -q "^$MD_ID"$'\t' "$MSW_MOONDECK_LEDGER" 2>/dev/null \
		|| printf '%s\t%s\n' "$MD_ID" "$change" >> "$MSW_MOONDECK_LEDGER"
}

msw_moondeck_restore() {
	local id change rc

	[[ -f $MSW_MOONDECK_LEDGER ]] || return 0
	while IFS=$'\t' read -r id change; do
		[[ -n $change ]] || continue
		msw_python moondeck "$MSW_MOONDECK_SETTINGS" restore "$change"
		rc=$?
		# 4 is no MoonDeck at all, so nothing to put back either.
		(( rc == 0 || rc == 4 )) || return 1
	done < "$MSW_MOONDECK_LEDGER"
	rm -f "$MSW_MOONDECK_LEDGER"
}
