#!/usr/bin/env bash
# Runs the tests: the Python parts on their own, then the command line from
# both ends in a sandbox, against a fake SwitchBot API.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
box="$(mktemp -d)"
failed=0
trap 'kill "${mock:-}" 2>/dev/null; rm -rf "$box"' EXIT

ok()   { printf 'ok  %s\n' "$1"; }
fail() { printf 'FAIL %s\n%s\n' "$1" "${2:-}"; failed=1; }

# check <name> <detail> <command...>
# The command has to succeed. The detail is shown when it does not.
check() {
	local name="$1" detail="$2"
	shift 2
	if "$@"; then ok "$name"; else fail "$name" "$detail"; fi
}

# expect <name> <pattern> <command...>
# The command has to succeed and print something matching the pattern.
expect() {
	local name="$1" pattern="$2" out
	shift 2
	if out="$("$@" 2>&1)" && grep -qE -- "$pattern" <<< "$out"; then
		ok "$name"
	else
		fail "$name" "$out"
	fi
}

# refuse <name> <pattern> <command...>
# The command has to fail, and say why.
refuse() {
	local name="$1" pattern="$2" out
	shift 2
	if ! out="$("$@" 2>&1)" && grep -qE -- "$pattern" <<< "$out"; then
		ok "$name"
	else
		fail "$name" "$out"
	fi
}

# --- the Python parts --------------------------------------------------------

if (cd "$root/tests" && python3 -m unittest -q test_python 2> "$box/unittest"); then
	ok "python tests"
else
	fail "python tests" "$(cat "$box/unittest")"
fi

# --- the command line --------------------------------------------------------

# A fake SwitchBot API, the one the Python tests use.
port_file="$box/mock-port"
python3 - "$root/tests" "$port_file" <<'EOF' &
import sys, time
sys.path.insert(0, sys.argv[1])
import test_python
server = test_python.start_mock()
with open(sys.argv[2], "w") as handle:
    handle.write(str(server.server_port))
while True:
    time.sleep(60)
EOF
mock=$!
for _ in {1..50}; do [[ -s $port_file ]] && break; sleep 0.1; done

export LC_ALL=C NO_COLOR=1
export MSW_SANDBOX="$box/sandbox" MSW_SB_API
MSW_SB_API="http://127.0.0.1:$(cat "$port_file")/v1.1"
msw() { "$root/scripts/sandbox.sh" "$@"; }
config="$box/sandbox/config/moondeck-switchbot-wol/config"
settings="$box/sandbox/config/moondeck/settings.json"

# The PC: on, a code, and the code on the Deck.
mkdir -p "$box/sandbox/etc" && printf 'User=alice\n' > "$box/sandbox/etc/host.conf"
expect "host enable" "login trigger is on. A wake-up from the Deck logs alice in" msw host enable
expect "host status" "Logs in +alice" msw host status
code="$(msw host code 2>/dev/null)"
check "host code" "$code" test "${code#msw1:}" != "$code"
expect "pair" "Paired" msw pair "$code"
check "pair writes the secret" "$(cat "$config")" \
	grep -q "^TriggerSecret=$(cat "$box/sandbox/etc/secret")$" "$config"
check "config is private" "$(stat -c %a "$config")" test "$(stat -c %a "$config")" = 600
refuse "pair refuses junk" "not a pairing code" msw pair "hello"

# A code that carries the SwitchBot too, as the menu on the PC makes it.
full="$(MSW_LIBDIR="$root/src/lib" bash -c '
	source "$MSW_LIBDIR/common.sh"; source "$MSW_LIBDIR/pairing.sh"
	msw_pair_encode TriggerPort=58471 TriggerSecret=0123456789abcdef0123456789abcdef \
		"Token=$1" "Secret=$2" Device=C0FFEE000001 "DeviceName=PC Power" Command=press
' _ "$(printf 'a%.0s' {1..96})" "$(printf 'b%.0s' {1..32})")"
expect "pair with SwitchBot" "SwitchBot set up: PC Power" msw pair "$full"
# A port nothing listens on, so the knock gives up quickly. The default one
# may be the real login trigger of this machine.
free="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
printf 'KnockTimeout=1\nTriggerPort=%s\n' "$free" >> "$config"
expect "status" "SwitchBot +PC Power" msw status

# MoonDeck: on, and back off to exactly what it was.
cp "$settings" "$box/settings.before"
expect "enable" "MoonDeck now wakes gaming-pc" msw enable
check "enable points MoonDeck at the shim" "$(cat "$settings")" \
	grep -q '"customWolExecPath": "'"$root"'/src/wake"' "$settings"
expect "status after enable" "SwitchBot wake-up +ON" msw status
expect "disable" "own Wake-on-LAN" msw disable
check "disable puts MoonDeck back" "$(cat "$settings")" \
	python3 -c 'import json, sys; sys.exit(json.load(open(sys.argv[1])) != json.load(open(sys.argv[2])))' \
	"$settings" "$box/settings.before"

# Pressing, and the wake-up MoonDeck runs: the second one within the cooldown
# must not press again.
expect "press" "got the command" msw press
rm -f "$box/sandbox/state/moondeck-switchbot-wol/last_press"
expect "wake" "SwitchBot: press sent" msw --shim gaming-pc 127.0.0.1 9 AA:BB:CC:DD:EE:FF
expect "wake twice" "not again" msw --shim gaming-pc 127.0.0.1 9 AA:BB:CC:DD:EE:FF
expect "log" "MoonDeck wakes gaming-pc" msw log

# The login trigger went on in the background, and gives up on its own.
for _ in {1..50}; do
	pgrep -f "$root/src/moondeck-switchbot-wol knock" > /dev/null || break
	sleep 0.2
done
expect "knock gives up" "login trigger: no answer from 127.0.0.1, gaming-pc" msw log

# A wrong token is reported, and fails the wake-up.
sed -i 's/^Token=.*/Token=wrong/' "$config"
rm -f "$box/sandbox/state/moondeck-switchbot-wol/last_press"
refuse "wake with a wrong token" "said no: Unauthorized" msw --shim gaming-pc 127.0.0.1 9 AA:BB:CC:DD:EE:FF

expect "host disable" "login trigger is off" msw host disable
expect "help" "host code" msw --help

exit "$failed"
