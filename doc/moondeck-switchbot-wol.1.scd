moondeck-switchbot-wol(1)

# NAME

moondeck-switchbot-wol - wake your PC from the Steam Deck with a SwitchBot

# SYNOPSIS

*moondeck-switchbot-wol* [_command_]

*moondeck-switchbot-wol host* [_command_]

# DESCRIPTION

MoonDeck wakes the PC it streams from with a Wake-on-LAN packet. Some boards,
network cards and BIOSes ignore that packet. A SwitchBot Bot on the power
button always works, so this program presses it instead.

The same program runs on both ends. On the Steam Deck it is what MoonDeck runs
in place of sending the packet. On the PC it sets up a login trigger, because
pressing the button only gets the PC to its login screen, and Sunshine does not
start before somebody logs in. Plain autologin would let anybody who switches
the PC on into the desktop. So the Deck proves that it did the waking, and only
then the PC logs in, once.

Run without a command it shows a menu. Everything it can be told is reachable
from there.

# COMMANDS ON THE DECK

*enable*
	Point MoonDeck's current PC at this program. MoonDeck is also told to
	wake only once, because a second press switches the PC off again, and to
	wait at least three minutes for the PC. What the settings said before is
	kept, and *disable* puts it back. MoonDeck reads its settings when Game
	Mode starts.

*disable*
	Give MoonDeck its own Wake-on-LAN back. A setting changed in MoonDeck
	since *enable* is left as it is.

*pair* [_code_]
	Pair with the PC. Without a code, wait until *host pair* on the PC finds
	this Deck, then show six digits to compare with the PC's. With a code,
	use the one that the PC shows when it cannot find the Deck. Either way
	the PC can send the SwitchBot setup as well, so nothing has to be typed
	on the Deck.

*setup*
	Set up the SwitchBot by hand: the token and the secret of the SwitchBot
	account, then the device from a list.

*press*
	Press the button now, to try it.

*status*
	Show what is set up, and what MoonDeck will do.

*log* [*-a*]
	Show the last wake-ups, or all of them.

*wake* _HOSTNAME_ _IP_ADDRESS_ _PORT_ _MAC_
	What MoonDeck runs, through _wake_ in the library folder. Presses the
	button, unless it was pressed within the cooldown, and then waits in the
	background for the PC to boot and log in. A non-zero exit tells MoonDeck
	that the wake-up failed.

# COMMANDS ON THE PC

These need root. Run by a user at a terminal, the program starts itself again
through *sudo*, *run0* or *doas*.

*host*
	The menu for this end.

*host enable*
	Turn the login trigger on: the socket that listens for the Deck, the unit
	that cleans up after a crash, and, when *ufw* is active, a rule that
	opens the port for the local network only.

*host disable*
	Turn it off again. The secret is kept, so a paired Deck stays paired.

*host pair*
	Look for a Deck that waits in *pair*, on this PC's network, and send it
	the secret of the login trigger. Both ends show six digits, and nothing
	is sent before the user on both ends says they match. It can send the
	SwitchBot setup as well. The credentials are not stored on the PC. When
	no Deck is found, it shows a pairing code instead.

*host code* [*--new*]
	Print the pairing code for the Deck, for a network where *host pair*
	cannot reach it. With *--new* a new secret is made first, which turns
	away every Deck paired before.

*host status*
	Show what is set up, and when the last wake-up came.

# PAIRING

While pairing, the Deck waits on TCP port 58472. The PC tries every address of
its network on that port, or the /24 around its own address in a bigger
network.

Both ends agree on a key with Diffie-Hellman (RFC 3526, group 14), and show six
digits made from it. Somebody in the middle would have a different key with
each end, so the digits would not match. The PC commits to its half of the key
before it sees the Deck's, so nobody can try keys until the digits match by
chance. Once the user on both ends says they match, the PC sends the pairing
code, encrypted and signed with the key.

# THE LOGIN TRIGGER

After the press, the Deck knocks on the PC every few seconds until it answers.
The PC sends a random challenge, and the Deck answers with an HMAC-SHA256 of it,
keyed with the secret from pairing. On a wake-up, the secret itself never goes
over the network.

The address MoonDeck uses for the PC is tried first, then its host name, so a
new address from the DHCP server changes nothing.

A Deck with the right answer gets *User=* set in the *[Autologin]* section of
the display manager's main config file, which wins over every file in its
conf.d folder. The display manager is restarted, and as soon as the session is
there, the file is put back the way it was. If the PC loses power in between, a
unit puts the file back at the next boot, before the display manager reads it.
Every other way of switching the PC on still asks for the password.

Plasma Login (_/etc/plasmalogin.conf_) and SDDM (_/etc/sddm.conf_) are
supported. With no *Session=* set, the session used last is started.

When a push topic is set, the PC sends a push through ntfy once Sunshine
answers on port 47989, or when the login did not work.

A secret store such as KWallet or GNOME Keyring is normally unlocked with the
password typed at login. With an automatic login nobody types one, so it stays
locked until something asks for it.

# FILES

_~/.config/moondeck-switchbot-wol/config_
	The Deck's settings, with the SwitchBot credentials. Private to the user.

_~/.local/state/moondeck-switchbot-wol/_
	The log, the time of the last press, and what *enable* changed in
	MoonDeck's settings.

_~/.config/moondeck/settings.json_
	MoonDeck's settings. *enable* changes four values of one PC in it.

_/etc/moondeck-switchbot-wol/host.conf_
	The PC's settings.

_/etc/moondeck-switchbot-wol/secret_
	The secret shared with the Deck. Readable by root only.

_/var/lib/moondeck-switchbot-wol/_
	What the display manager's config said before a login, while one is
	under way, and the result of the last one.

# ENVIRONMENT

*NO_COLOR*
	Disables colour.

# REQUIREMENTS

Bash 4.2 or newer, Python 3 and GNU coreutils on both ends. On the Deck,
MoonDeck. On the PC, systemd and Plasma Login or SDDM. A SwitchBot Bot, and a
SwitchBot hub with *Cloud Services* on for the Bot.

# SEE ALSO

*systemctl*(1), *ufw*(8), *sddm.conf*(5)

# AUTHORS

Felitendo. Source and issue tracker at
https://github.com/Felitendo/moondeck-switchbot-wol
