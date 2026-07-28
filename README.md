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

It will:

1. Point you at **Profile → Preferences → tap "App Version" 10 times → Developer Options** in the SwitchBot app, where the token and the client secret live
2. Fetch your devices and let you pick one
3. Ask whether the Bot runs in press mode or switch mode
4. Write the credentials to `~/.config/moondeck-switchbot/config` (mode 600)
5. Install the wake-up script, by default to `~/moondeck-switchbot-wol.sh`
6. Optionally fire a test command so you can hear the Bot click

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

Run it without sudo in front, it asks for root itself. `sudo curl … | sudo bash` would not help anyway: sudo closes the descriptors a downloaded script may live on, so the script hands sudo a real path it downloaded to.

It asks which user and session to log in, generates the secret, installs a
socket-activated systemd service and, if `ufw` is active, opens the port for
your local subnet only. Then re-run `./install.sh` on the Deck and answer yes
when it offers the login trigger, using the secret the host printed.

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

Worth knowing: whoever holds the Deck can log into your host. And with
autologin, PAM never sees your password, so KDE Wallet cannot be unlocked for
you and will ask separately when an application first wants a stored secret.

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
| `LOGIN_TRIGGER_HOST` | Host address; empty means the one MoonDeck passes in |
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
