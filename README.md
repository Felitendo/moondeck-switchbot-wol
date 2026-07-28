# moondeck-switchbot-wol

Wake your gaming PC from the Steam Deck with a [SwitchBot](https://www.switch-bot.com/) instead of Wake-on-LAN.

[MoonDeck](https://github.com/FrogTheFrog/moondeck) can call a custom executable in place of sending a magic packet. This repository ships that executable: it asks the SwitchBot cloud to physically push the power button of your host PC. Useful when the mainboard, the NIC or the BIOS refuses to do Wake-on-LAN properly, and the button is the only thing that reliably works.

The installer is a small wizard — it explains where to find your API credentials, fetches your device list and lets you pick the right SwitchBot from a list, so you never have to look up a device ID by hand. It speaks English and German and follows the system locale.

## Requirements

- A SwitchBot Bot mounted on the power button of the host PC
- A SwitchBot Hub (Hub Mini, Hub 2, …) — the Bot itself is Bluetooth only, the cloud API can only reach it through a hub
- **Cloud Services** enabled for the Bot in the SwitchBot app
- `curl`, `openssl` and `python3` on the Steam Deck (all present on SteamOS)
- Internet access on the Deck at wake-up time

## Install

Run this in desktop mode on the Steam Deck:

```bash
curl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/install.sh | bash
```

Nothing is left behind: the installer pulls the few files it needs into a temporary directory and removes it again when it is done. A checkout works just as well — `./install.sh` uses the files next to it when they are there.

Piping into bash normally breaks a wizard, because standard input is then the script rather than you. The installer notices and re-runs itself from a downloaded copy with the terminal back on standard input, so the prompts work. `bash <(curl …)` is fine too, in shells that have process substitution — fish does not.

The wizard uses `kdialog` or `zenity` when a graphical session is available. Add `--cli` for plain terminal prompts.

First it asks whether you have a pairing token from the host — see below, it is
worth it, because everything in that token is one thing less to type on a
handheld. Without one it asks for the lot:

1. Point you at **Profile → Preferences → tap "App Version" 10 times → Developer Options** in the SwitchBot app, where the token and the client secret live
2. Fetch your devices and let you pick one
3. Ask whether the Bot runs in press mode or switch mode

Either way it then writes the credentials to `~/.config/moondeck-switchbot/config`
(mode 600), installs the wake-up script — by default to
`~/moondeck-switchbot-wol.sh` — and offers to fire a test command so you can hear
the Bot click.

## Set up MoonDeck

In MoonDeck, go to **Settings → WOL Settings**:

1. Enable *Use custom WOL executable*
2. Set the path to the installed script (`/home/deck/moondeck-switchbot-wol.sh` by default)

The WOL port is ignored from then on. The default install path is deliberately not hidden — MoonDeck's Browse dialog cannot enter dotted folders.

MoonDeck runs the executable as `script <HOSTNAME> <IP_ADDRESS> <PORT> <MAC>` and treats any non-zero exit code as a failed wake-up. The arguments are only logged here; everything the script needs comes from its config file.

## Optional: log in automatically, but only for wake-ups

Pressing the power button gets you as far as the login screen. Sunshine only
starts once a session exists, so something has to log in — but switching on
autologin would also let anyone who walks up to the machine straight into your
desktop.

The trigger in `host/` solves that. The host cannot tell who pressed its power
button, so the proof comes from the Deck afterwards:

1. The Deck presses the SwitchBot as usual
2. The host boots to its normal login screen and asks for a password
3. In the background the Deck keeps knocking until the host answers, then
   proves it caused the wake-up with a challenge and response
4. The host logs the configured user in **once** and immediately puts the
   password prompt back

Switch the machine on by hand and step 3 never happens, so you type your
password. The secret itself never goes over the network — the host sends a
nonce, the Deck answers with `hmac_sha256(secret, nonce)`, so nothing worth
replaying is ever on the wire.

On the host:

```bash
curl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/host/install-host.sh | bash
```

Run it without sudo in front. It asks its questions as you, in the same dialog
windows the Deck side uses, and only calls sudo once at the end for the
installation itself — root has no session to draw a window on, and prompting for
API credentials in a terminal is exactly where pasting gets awkward. What sudo
gets handed is a mode 600 file with the answers, not a command line full of
secrets, and the SwitchBot credentials never reach the privileged half at all.

It asks which user and session to log in, generates the secret, installs a
socket-activated systemd service and, if `ufw` is active, opens the port for
your local subnet only. It also offers to take the SwitchBot side off your
hands: enter the API credentials here, pick the device from the list it
fetches, and all of it goes into the pairing token as well. Nothing of that is
stored on the host — it only travels inside the token.

At the end it prints that token: one line carrying the port, the trigger
secret, the host address and, if you said yes, the SwitchBot setup. On the Deck
you then answer yes to the very first question, paste it, and the wizard skips
everything the token already knows. Typing an API token on a handheld keyboard
is exactly the kind of thing this avoids.

An existing installation can hand out its token again at any time, without
changing anything. That one carries the trigger only, since the SwitchBot
credentials are deliberately not kept here:

```bash
curl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/host/install-host.sh | bash -s -- --token
```

DHCP is not a problem. The address inside the token is only the last resort:
the Deck first tries the address MoonDeck passed to the wake-up script, then
the host name, and only then the noted one. Whatever MoonDeck itself reaches
the host on works for the trigger too.

What it changes on the host: only the `User=` entry in the `[Autologin]`
section of `/etc/plasmalogin.conf` (or `/etc/sddm.conf`), added when a valid
trigger arrives and removed again after login. Everything else in that file is
left alone. The previous state is kept on disk, and a small unit disarms a
leftover autologin at boot **before** the display manager reads it — so a crash
between the trigger and the login cannot leave the machine permanently logging
itself in.

Remove all of it again with:

```bash
curl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/host/install-host.sh | bash -s -- --uninstall
```

### Getting told when the host is ready

The host installer can optionally send a push through [ntfy](https://ntfy.sh)
when the wake-up is done. It waits for the session to appear and then for
Sunshine's port to accept a connection, so the message means "connect now"
rather than "the button was pressed". Different messages go out when the login
did not happen or when nothing is listening on the stream port.

The server defaults to `https://ntfy.sh`, any self-hosted instance works just as
well, and leaving the topic empty keeps the whole thing off. Pick a topic name
nobody can guess: on a public server, knowing the topic is enough to read your
notifications and to post into them.

This only covers wake-ups that went through the trigger. A machine switched on
by hand never runs the agent and therefore never reports in.

Beyond `User` and `Session`, `/etc/moondeck-login-agent/config` takes
`NtfyServer`, `NtfyTopic`, `NtfyTitle`, `NtfyMessage`, `NtfyMessageNoStream`,
`NtfyMessageFailed` and `ReadyPort` (`47989`, Sunshine's port; `0` skips the
wait).

### Password protected keyrings

Whoever holds the Deck can log into your host — that is the deal you are making.

The other consequence is less obvious: an automatic login means PAM never sees
a password, so it has none to pass on to `pam_gnome_keyring` or `pam_kwallet`.
Any keyring that has its own password therefore stays locked, and the first
application that wants a stored secret opens a password dialog on the desktop —
mid-stream, if you are unlucky. This is not specific to this project, it is what
automatic login does everywhere.

There are two ways out, and the narrow one is usually the better trade:

- **Take the offending application out of the keyring.** Electron apps accept
  `--password-store=basic` and then keep their secrets in their own config
  directory, so the keyring keeps its password and stays encrypted for
  everything else. What you give up is the protection on that one
  application's token.
- **Remove the keyring password.** In Seahorse, right-click the keyring,
  *Change Password*, leave the new one empty; KWallet has the same option in
  its settings. This fixes it for every application at once, but the contents
  then sit unencrypted in `~/.local/share/keyrings`. That only matters to
  someone who gets at the disk or a backup — on a machine without disk
  encryption, they would have everything else anyway.

The host installer looks for such a keyring and spells this out at the end,
rather than letting the dialog surprise you later.

## Configuration

`~/.config/moondeck-switchbot/config` is a shell fragment:

| Key | Meaning |
| --- | --- |
| `TOKEN` | SwitchBot API token |
| `SECRET` | SwitchBot client secret |
| `DEVICE_ID` | ID of the device to trigger |
| `COMMAND` | `press` for a Bot in press mode, `turnOn` for switch mode or a smart plug |
| `COOLDOWN` | Seconds during which no second press is sent, `180` by default, `0` disables it |
| `INSTALL_PATH` | Where the script was installed, used by `uninstall.sh` |
| `LOGIN_TRIGGER_SECRET` | Secret from `host/install-host.sh`; empty disables the whole trigger |
| `LOGIN_TRIGGER_PORT` | Port the trigger listens on, `58471` by default |
| `LOGIN_TRIGGER_HOST` | Fallback address, tried after the ones MoonDeck passes in |
| `LOGIN_TRIGGER_TIMEOUT` | Seconds to keep knocking while the host boots, `240` by default |

The cooldown exists because a power button is not a magic packet: sending the same packet twice is harmless, pressing the button again while the machine is booting is not. Re-run `install.sh` at any time to change any of this.

## Troubleshooting

- **The device list is empty.** The Bot needs to be paired with a hub and have *Cloud Services* switched on in the app.
- **The Bot clicks but the PC does not start.** That is a mounting problem, not a software one — check that the arm actually reaches the button and that the Bot's battery is not empty.
- **MoonDeck reports a failed wake-up.** Check `/tmp/moondeck-switchbot-<uid>.log`, it records every invocation and the raw API response. You can also run the script by hand with `--test`.
- **MoonDeck gives up before the PC has booted.** Raise the timeouts in MoonDeck's Buddy and Runner settings. A cold boot takes far longer than waking from sleep, and the defaults are tuned for the latter.
- **Nothing happens on the second launch attempt.** That is the cooldown doing its job. Lower or disable `COOLDOWN` if you really want every attempt to press.
- **The host boots but stays on the login screen.** Check the same log on the Deck: it records whether the trigger was handed off and what the host answered. `DENIED` means the secret does not match, no answer at all means the port is not reachable — `journalctl -u 'moondeck-login-agent@*'` on the host shows its side.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/uninstall.sh | bash
```

Removes the script and offers to delete the stored credentials. Remember to switch *Use custom WOL executable* back off in MoonDeck.

## License

BSD 3-Clause, see [LICENSE](LICENSE).
