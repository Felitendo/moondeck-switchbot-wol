#!/usr/bin/env bash
#
# Tiny string table. The language follows the system locale and can be forced
# with MOONDECK_SWITCHBOT_LANG=en|de.
#
# All strings are printf format strings, so a literal percent sign has to be
# written as %%.

msb_detect_lang() {
    if [[ -n ${MOONDECK_SWITCHBOT_LANG:-} ]]; then
        printf '%s' "$MOONDECK_SWITCHBOT_LANG"
        return
    fi
    case ${LC_ALL:-${LC_MESSAGES:-${LANG:-en_US.UTF-8}}} in
        de*) printf 'de' ;;
        *) printf 'en' ;;
    esac
}

MSB_LANG=$(msb_detect_lang)

declare -A MSB_EN=(
    [app_title]="MoonDeck SwitchBot Wake-Up"
    [usage]="Usage: install.sh [--cli] [--help]\n\n  --cli   use plain terminal prompts instead of a dialog window\n  --help  show this text\n"
    [dep_missing]="Required command not found: %s\n\nInstall it and run the installer again."
    [welcome]="This wizard installs a small script that MoonDeck runs instead of sending a Wake-on-LAN packet. The script asks your SwitchBot to press the power button of your gaming PC.\n\nWhat you need:\n  • a Bot paired with a SwitchBot Hub\n  • 'Cloud Services' enabled for that Bot in the SwitchBot app\n  • internet access on this device"
    [creds_intro]="Now grab your API credentials. In the SwitchBot app go to:\n\n    Profile → Preferences → tap 'App Version' 10 times → Developer Options\n\nTap 'Get Token' and copy both values.\n\nThey are stored locally in\n%s\nand are only ever sent to the SwitchBot API."
    [ask_token]="Paste your SwitchBot token:"
    [ask_secret]="Paste your SwitchBot client secret:"
    [input_empty]="Nothing entered - aborting."
    [cancelled]="Cancelled."
    [fetching]="Asking the SwitchBot API for your devices..."
    [api_unreachable]="Could not reach the SwitchBot API. Check the internet connection on this device."
    [api_error]="The SwitchBot API returned an error.\n\nStatus code: %s\n%s\n\nDouble-check the token and the secret."
    [no_devices]="Your account does not list any devices.\n\nA Bot only appears here once it is paired with a SwitchBot Hub and 'Cloud Services' is switched on for it in the app."
    [choose_device]="Which device should press the power button?"
    [ask_mode]="How is that device set up in the SwitchBot app?"
    [mode_press]="Press mode - the arm pushes and returns (recommended)"
    [mode_switch]="Switch mode or smart plug - turn on"
    [ask_path]="Where should the script be installed?\n\nMoonDeck's Browse dialog cannot enter hidden folders, so keep it somewhere visible."
    [path_exists]="%s already exists.\n\nOverwrite it?"
    [write_failed]="Could not write to %s"
    [test_ask]="Send a test command right now?\n\nYour SwitchBot will physically press the button."
    [test_ok]="The SwitchBot accepted the command."
    [test_failed]="The test failed:\n\n%s"
    [done]="Done.\n\nOpen MoonDeck on your Steam Deck and go to Settings → WOL Settings:\n\n  1. turn on 'Use custom WOL executable'\n  2. set the path to:\n\n     %s\n\nThe WOL port is ignored from now on.\n\nIf MoonDeck gives up before the PC has finished booting, raise the timeouts in the Buddy and Runner settings - a cold boot takes a lot longer than waking from sleep."
    [uninstall_intro]="This removes the wake-up script from your system."
    [uninstall_none]="Nothing to remove - no installation found."
    [uninstall_ask_config]="Delete the saved token and secret as well?\n\n%s"
    [uninstall_done]="Removed. Remember to switch 'Use custom WOL executable' back off in MoonDeck."
)

declare -A MSB_DE=(
    [app_title]="MoonDeck SwitchBot Wake-Up"
    [usage]="Aufruf: install.sh [--cli] [--help]\n\n  --cli   einfache Terminal-Abfragen statt Dialogfenster\n  --help  diesen Text anzeigen\n"
    [dep_missing]="Benötigter Befehl nicht gefunden: %s\n\nInstalliere ihn und starte den Installer erneut."
    [welcome]="Dieser Assistent installiert ein kleines Skript, das MoonDeck anstelle eines Wake-on-LAN-Pakets ausführt. Das Skript lässt deinen SwitchBot den Power-Knopf deines Gaming-PCs drücken.\n\nWas du brauchst:\n  • einen Bot, der mit einem SwitchBot Hub gekoppelt ist\n  • aktivierte 'Cloud-Dienste' für diesen Bot in der SwitchBot-App\n  • eine Internetverbindung auf diesem Gerät"
    [creds_intro]="Jetzt brauchst du deine API-Zugangsdaten. In der SwitchBot-App:\n\n    Profil → Einstellungen → 10× auf 'App-Version' tippen → Entwickleroptionen\n\nDort auf 'Token abrufen' tippen und beide Werte kopieren.\n\nSie werden lokal in\n%s\ngespeichert und nur an die SwitchBot-API geschickt."
    [ask_token]="SwitchBot-Token einfügen:"
    [ask_secret]="SwitchBot Client Secret einfügen:"
    [input_empty]="Nichts eingegeben - Abbruch."
    [cancelled]="Abgebrochen."
    [fetching]="Frage die Geräteliste bei der SwitchBot-API ab..."
    [api_unreachable]="Die SwitchBot-API ist nicht erreichbar. Prüfe die Internetverbindung dieses Geräts."
    [api_error]="Die SwitchBot-API hat einen Fehler gemeldet.\n\nStatuscode: %s\n%s\n\nPrüfe Token und Secret noch einmal."
    [no_devices]="In deinem Konto sind keine Geräte hinterlegt.\n\nEin Bot taucht hier erst auf, wenn er mit einem SwitchBot Hub gekoppelt ist und die 'Cloud-Dienste' in der App für ihn eingeschaltet sind."
    [choose_device]="Welches Gerät soll den Power-Knopf drücken?"
    [ask_mode]="Wie ist das Gerät in der SwitchBot-App eingestellt?"
    [mode_press]="Drücken-Modus - der Arm drückt und fährt zurück (empfohlen)"
    [mode_switch]="Schalter-Modus oder Smart Plug - einschalten"
    [ask_path]="Wohin soll das Skript installiert werden?\n\nDer Browse-Dialog von MoonDeck kann keine versteckten Ordner öffnen, also lass es an einer sichtbaren Stelle."
    [path_exists]="%s existiert bereits.\n\nÜberschreiben?"
    [write_failed]="Konnte nicht nach %s schreiben"
    [test_ask]="Jetzt einen Testbefehl schicken?\n\nDein SwitchBot drückt dabei wirklich den Knopf."
    [test_ok]="Der SwitchBot hat den Befehl angenommen."
    [test_failed]="Der Test ist fehlgeschlagen:\n\n%s"
    [done]="Fertig.\n\nÖffne MoonDeck auf dem Steam Deck und gehe zu Einstellungen → WOL Settings:\n\n  1. 'Use custom WOL executable' einschalten\n  2. als Pfad eintragen:\n\n     %s\n\nDer WOL-Port wird ab jetzt ignoriert.\n\nFalls MoonDeck aufgibt, bevor der PC durchgebootet hat, dreh die Timeouts in den Buddy- und Runner-Settings hoch - ein Kaltstart dauert deutlich länger als das Aufwachen aus dem Standby."
    [uninstall_intro]="Damit wird das Wake-up-Skript wieder von deinem System entfernt."
    [uninstall_none]="Nichts zu entfernen - keine Installation gefunden."
    [uninstall_ask_config]="Auch den gespeicherten Token und das Secret löschen?\n\n%s"
    [uninstall_done]="Entfernt. Denk daran, 'Use custom WOL executable' in MoonDeck wieder auszuschalten."
)

# t <key> [printf arguments...]
t() {
    local key=$1
    shift
    local fmt
    if [[ $MSB_LANG == de ]]; then
        fmt=${MSB_DE[$key]:-${MSB_EN[$key]:-$key}}
    else
        fmt=${MSB_EN[$key]:-$key}
    fi
    # shellcheck disable=SC2059
    printf "$fmt" "$@"
}
