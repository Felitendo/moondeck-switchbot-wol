# moondeck-switchbot-wol

Wake your gaming PC from the Steam Deck with a [SwitchBot](https://www.switch-bot.com/) instead of Wake-on-LAN.

[MoonDeck](https://github.com/FrogTheFrog/moondeck) can call a custom executable in place of sending a magic packet. This repository ships that executable: it asks the SwitchBot cloud to physically push the power button of your host PC. Useful when the mainboard, the NIC or the BIOS refuses to do Wake-on-LAN properly, and the button is the only thing that reliably works.

The installer is a small wizard — it explains where to find your API credentials, fetches your device list and lets you pick the right SwitchBot from a list.

## Requirements

- A SwitchBot Bot mounted on the power button of the host PC
- A SwitchBot Hub (Hub Mini, Hub 2, …) — the Bot itself is Bluetooth only, the cloud API can only reach it through a hub
- **Cloud Services** enabled for the Bot in the SwitchBot app
- `curl`, `openssl` and `python3` on the Steam Deck (all present on SteamOS)

## Install

Run this in desktop mode on the Steam Deck:

```bash
curl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/install.sh | bash
```

The Installer will walk you through everything you need to know.


## Optional (recommended): log in automatically, but only for wake-ups from the Deck

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


Install on the host PC:

```bash
curl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/host/install-host.sh | bash
```

It asks which user and session to log in, generates the secret, installs a
socket-activated systemd service and, if `ufw` is active, opens the port for
your local subnet only. It also offers to take the SwitchBot side off your
hands: enter the API credentials here, pick the device from the list it
fetches, and all of it goes into the pairing token as well. Nothing of that is
stored on the host — it only travels inside the token.

At the end it hands you that token — one line carrying the port, the trigger
secret, the host address and, if you said yes, the SwitchBot setup. On the Deck
you then answer yes to the very first question, paste it, and the wizard skips
everything the token already knows.

An existing installation can hand out its token again at any time, without
changing anything:

```bash
curl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/host/install-host.sh | bash -s -- --token
```

Remove all of it again with:

```bash
curl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/host/install-host.sh | bash -s -- --uninstall
```

### Getting told when the host is ready

The host installer can optionally send a push through [ntfy](https://ntfy.sh)
when the wake-up is done.

The server defaults to `https://ntfy.sh`, any self-hosted instance works just as
well, and leaving the topic empty keeps the whole thing off. Pick a topic name
nobody can guess: on a public server, knowing the topic is enough to read your
notifications and to post into them.

This only covers wake-ups that went through the trigger. A machine switched on
by hand never runs the agent and therefore never reports in.


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
