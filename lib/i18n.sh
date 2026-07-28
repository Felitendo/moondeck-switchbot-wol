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
    [testing]="Sending the test command..."
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
    [token_ask]="Do you have a pairing token from the host?\n\nThe installer over there can put the whole setup into one line - SwitchBot credentials, the device and the login trigger. Say no to enter everything by hand instead."
    [host_sb_ask]="Should the pairing token carry the SwitchBot setup as well?\n\nThen the Deck only has to paste one line, instead of typing API credentials on a handheld keyboard. Nothing of it is stored on this machine, it only travels inside the token."
    [host_creds_intro]="In the SwitchBot app go to:\n\n    Profile → Preferences → tap 'App Version' 10 times → Developer Options\n\nTap 'Get Token' and copy both values.\n\nThey are not kept on this machine - they only end up inside the pairing token."
    [trigger_token]="Paste the pairing token the host installer printed:"
    [trigger_bad_token]="That does not look like a pairing token.\n\nIt is the single long line the host installer printed at the end, and it can be produced again there at any time."
    [host_need_root]="This has to run as root, it installs a system service:\n\n    sudo bash ./host/install-host.sh"
    [host_welcome]="This sets up the one-shot login trigger on the machine that gets woken up.\n\nAfter this, waking the host from the Steam Deck logs you in automatically, while switching the machine on by hand still asks for your password. The Deck proves that the wake-up was its doing, using a shared secret that never travels over the network."
    [host_ask_user]="Which user should be logged in?"
    [host_unknown_user]="There is no user called %s on this system."
    [host_no_sessions]="No desktop sessions found under /usr/share/wayland-sessions or /usr/share/xsessions."
    [host_ask_session]="Which session should be started?"
    [host_ask_port]="Which port should the trigger listen on?"
    [host_bad_port]="%s is not a usable port number."
    [host_ufw_added]="Opened the port in ufw for %s on port %s. The trigger is not reachable from outside your network."
    [host_ufw_skipped]="No active ufw found. If a firewall is in the way, port %s has to be reachable from the Steam Deck."
    [host_done]="Done, the trigger is listening.%s\n\nThe line below goes into the installer on your Steam Deck. It carries everything the Deck needs: the port, the trigger secret, this machine's address and, if you said yes, the SwitchBot setup as well.\n\nThe address in it is only a fallback - the Deck first tries whatever MoonDeck uses to reach this host, so a new DHCP lease changes nothing.\n\nRemove all of it again with:\ncurl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/host/install-host.sh | bash -s -- --uninstall"
    [host_ntfy_ask]="Send a push notification through ntfy once the host is up and ready to stream?"
    [host_ntfy_topic]="ntfy topic (anyone who knows it can read your notifications):"
    [host_ntfy_server]="ntfy server:"
    [host_ntfy_title]="Host is ready"
    [host_ntfy_ready]="%s finished booting, is logged in and Sunshine is listening."
    [host_ntfy_nostream]="%s is logged in, but nothing is listening on the stream port."
    [host_ntfy_failed]="%s booted, but logging in did not work."
    [host_keyring_warning]="One more thing: this machine has a secret store (%s). If it still has a password, this concerns you.\n\nSuch a store is normally unlocked with your password while you log in. With an automatic login nobody types one, so it stays locked and the first application that wants a stored secret pops up a password dialog - possibly in the middle of a stream.\n\nTwo ways out:\n\n  1. Take the affected application out of the keyring. Electron apps accept --password-store=basic and keep their secrets in their own config instead. The rest of the keyring stays encrypted. Best when it is only one or two applications.\n\n  2. Remove the password from the keyring: in Seahorse, right-click it, choose Change Password and leave the new one empty (KWallet has the same option in its settings). Fixes it for every application, but its contents then sit unencrypted on disk. That matters if someone gets hold of the disk or a backup - though without disk encryption they would have everything else anyway."
    [host_sudo_hint]="The installation itself needs root, sudo will ask for your password in the terminal."
    [host_privileged_failed]="The privileged part did not finish. Nothing was changed."
    [host_token_clipboard]="\n\nIt is already in your clipboard."
    [host_secret_kept]="Keeping the existing secret - the pairing token already on your Deck stays valid."
    [host_not_installed]="No login trigger is installed on this machine yet."
    [host_token]="This line goes into the installer on your Steam Deck.%s"
    [host_uninstall_done]="The login trigger has been removed and the password prompt is back for every way of starting this machine."
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
    [testing]="Schicke den Testbefehl..."
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
    [token_ask]="Hast du einen Kopplungs-Token vom PC?\n\nDer Installer dort drüben kann die komplette Einrichtung in eine Zeile packen - SwitchBot-Zugangsdaten, Gerät und Login-Trigger. Sag nein, um stattdessen alles von Hand einzugeben."
    [host_sb_ask]="Soll der Kopplungs-Token auch die SwitchBot-Einrichtung enthalten?\n\nDann muss auf dem Deck nur eine Zeile eingefügt werden, statt API-Zugangsdaten auf einer Handheld-Tastatur zu tippen. Auf diesem Rechner bleibt davon nichts, es steckt nur im Token."
    [host_creds_intro]="In der SwitchBot-App:\n\n    Profil → Einstellungen → 10× auf 'App-Version' tippen → Entwickleroptionen\n\nDort auf 'Token abrufen' tippen und beide Werte kopieren.\n\nSie bleiben nicht auf diesem Rechner - sie landen nur im Kopplungs-Token."
    [trigger_token]="Den Kopplungs-Token einfügen, den der Installer auf dem PC ausgegeben hat:"
    [trigger_bad_token]="Das sieht nicht nach einem Kopplungs-Token aus.\n\nGemeint ist die eine lange Zeile, die der Installer auf dem PC am Ende ausgegeben hat; dort lässt sie sich jederzeit neu erzeugen."
    [host_need_root]="Das muss als root laufen, es installiert einen Systemdienst:\n\n    sudo bash ./host/install-host.sh"
    [host_welcome]="Das richtet den Einmal-Login-Trigger auf dem Rechner ein, der geweckt wird.\n\nDanach meldet dich ein Aufwecken vom Steam Deck automatisch an, während der Rechner beim Einschalten von Hand weiterhin nach deinem Passwort fragt. Das Deck weist sich dafür mit einem gemeinsamen Geheimnis aus, das nie über das Netz geht."
    [host_ask_user]="Welcher Benutzer soll angemeldet werden?"
    [host_unknown_user]="Es gibt auf diesem System keinen Benutzer namens %s."
    [host_no_sessions]="Unter /usr/share/wayland-sessions und /usr/share/xsessions wurden keine Sitzungen gefunden."
    [host_ask_session]="Welche Sitzung soll gestartet werden?"
    [host_ask_port]="Auf welchem Port soll der Trigger lauschen?"
    [host_bad_port]="%s ist keine brauchbare Portnummer."
    [host_ufw_added]="Port in ufw für %s auf Port %s geöffnet. Von außerhalb deines Netzes ist der Trigger nicht erreichbar."
    [host_ufw_skipped]="Kein aktives ufw gefunden. Falls eine Firewall dazwischen ist, muss Port %s vom Steam Deck aus erreichbar sein."
    [host_done]="Fertig, der Trigger lauscht.%s\n\nDie Zeile unten gehört in den Installer auf deinem Steam Deck. Darin steckt alles, was das Deck braucht: Port, Trigger-Geheimnis, die Adresse dieses Rechners und, falls du zugestimmt hast, auch die SwitchBot-Einrichtung.\n\nDie Adresse darin ist nur die Rückfallebene - das Deck probiert zuerst die, über die MoonDeck den Host erreicht, ein neuer DHCP-Lease ändert also nichts.\n\nAlles wieder entfernen mit:\ncurl -fsSL https://raw.githubusercontent.com/Felitendo/moondeck-switchbot-wol/main/host/install-host.sh | bash -s -- --uninstall"
    [host_ntfy_ask]="Eine Push-Benachrichtigung über ntfy schicken, sobald der Rechner oben und streambereit ist?"
    [host_ntfy_topic]="ntfy-Topic (wer es kennt, kann deine Benachrichtigungen mitlesen):"
    [host_ntfy_server]="ntfy-Server:"
    [host_ntfy_title]="PC ist bereit"
    [host_ntfy_ready]="%s ist hochgefahren, angemeldet und Sunshine lauscht."
    [host_ntfy_nostream]="%s ist angemeldet, aber auf dem Stream-Port lauscht nichts."
    [host_ntfy_failed]="%s ist hochgefahren, aber die Anmeldung hat nicht geklappt."
    [host_keyring_warning]="Noch eine Sache: auf diesem Rechner liegt ein Schlüsselspeicher (%s). Falls der noch ein Passwort hat, betrifft dich das hier.\n\nSo einer wird sonst beim Anmelden mit deinem Passwort aufgeschlossen. Beim automatischen Login tippt niemand eins, also bleibt er zu, und die erste Anwendung, die ein gespeichertes Geheimnis braucht, öffnet ein Passwortfenster - im Zweifel mitten im Stream.\n\nZwei Wege dagegen:\n\n  1. Die betroffene Anwendung aus dem Schlüsselbund nehmen. Electron-Apps akzeptieren --password-store=basic und legen ihre Geheimnisse dann selbst ab. Der Rest des Schlüsselbunds bleibt verschlüsselt. Am besten, wenn es nur um ein, zwei Anwendungen geht.\n\n  2. Dem Schlüsselbund das Passwort nehmen: in Seahorse Rechtsklick, Passwort ändern, neues leer lassen (bei KWallet steht dieselbe Option in den Einstellungen). Löst es für jede Anwendung, aber der Inhalt liegt danach unverschlüsselt auf der Platte. Das zählt, wenn jemand an die Platte oder ein Backup kommt - ohne Plattenverschlüsselung hätte er allerdings ohnehin alles andere."
    [host_sudo_hint]="Die Installation selbst braucht root, sudo fragt gleich im Terminal nach deinem Passwort."
    [host_privileged_failed]="Der Teil mit Root-Rechten ist nicht durchgelaufen. Es wurde nichts geändert."
    [host_token_clipboard]="\n\nSie liegt bereits in deiner Zwischenablage."
    [host_secret_kept]="Das bestehende Geheimnis bleibt - der Token, der schon auf dem Deck liegt, gilt weiter."
    [host_not_installed]="Auf diesem Rechner ist noch kein Login-Trigger installiert."
    [host_token]="Diese Zeile gehört in den Installer auf deinem Steam Deck.%s"
    [host_uninstall_done]="Der Login-Trigger ist entfernt, es wird wieder bei jedem Start nach dem Passwort gefragt."
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
