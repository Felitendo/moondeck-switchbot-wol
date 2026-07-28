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
git clone https://github.com/Felitendo/moondeck-switchbot-wol.git && cd moondeck-switchbot-wol && ./install.sh
```

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

The cooldown exists because a power button is not a magic packet: sending the same packet twice is harmless, pressing the button again while the machine is booting is not. Re-run `install.sh` at any time to change any of this.

## Troubleshooting

- **The device list is empty.** The Bot needs to be paired with a hub and have *Cloud Services* switched on in the app.
- **The Bot clicks but the PC does not start.** That is a mounting problem, not a software one — check that the arm actually reaches the button and that the Bot's battery is not empty.
- **MoonDeck reports a failed wake-up.** Check `/tmp/moondeck-switchbot-<uid>.log`, it records every invocation and the raw API response. You can also run the script by hand with `--test`.
- **MoonDeck gives up before the PC has booted.** Raise the timeouts in MoonDeck's Buddy and Runner settings. A cold boot takes far longer than waking from sleep, and the defaults are tuned for the latter.
- **Nothing happens on the second launch attempt.** That is the cooldown doing its job. Lower or disable `COOLDOWN` if you really want every attempt to press.

## Uninstall

```bash
./uninstall.sh
```

Removes the script and offers to delete the stored credentials. Remember to switch *Use custom WOL executable* back off in MoonDeck.

## License

BSD 3-Clause, see [LICENSE](LICENSE).
