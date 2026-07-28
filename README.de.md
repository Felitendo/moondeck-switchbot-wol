# moondeck-switchbot-wol

*[English version](README.md)*

Den Gaming-PC vom Steam Deck aus mit einem [SwitchBot](https://www.switch-bot.com/) starten statt per Wake-on-LAN.

[MoonDeck](https://github.com/FrogTheFrog/moondeck) kann anstelle eines Magic Packets ein eigenes Programm aufrufen. Genau das liegt hier: Es lässt den SwitchBot den Power-Knopf des Host-PCs physisch drücken. Praktisch, wenn Mainboard, Netzwerkkarte oder BIOS bei Wake-on-LAN zicken und der Knopf das Einzige ist, was zuverlässig funktioniert.

Der Installer ist ein kleiner Assistent — er zeigt dir, wo die API-Zugangsdaten stecken, holt deine Geräteliste ab und lässt dich den richtigen SwitchBot auswählen, damit du keine Device-ID von Hand heraussuchen musst. Er spricht Deutsch und Englisch und richtet sich nach der Systemsprache.

## Voraussetzungen

- Ein SwitchBot Bot, der auf dem Power-Knopf des Host-PCs klebt
- Ein SwitchBot Hub (Hub Mini, Hub 2, …) — der Bot selbst kann nur Bluetooth, die Cloud-API erreicht ihn ausschließlich über einen Hub
- Aktivierte **Cloud-Dienste** für den Bot in der SwitchBot-App
- `curl`, `openssl` und `python3` auf dem Steam Deck (unter SteamOS alles vorhanden)
- Internetverbindung auf dem Deck zum Zeitpunkt des Aufweckens

## Installation

Im Desktop-Modus des Steam Decks:

```bash
git clone https://github.com/Felitendo/moondeck-switchbot-wol.git && cd moondeck-switchbot-wol && ./install.sh
```

Der Assistent nutzt `kdialog` oder `zenity`, sobald eine grafische Sitzung läuft. Mit `--cli` bekommst du stattdessen einfache Terminal-Abfragen.

Er wird:

1. dir den Weg zu **Profil → Einstellungen → 10× auf „App-Version" tippen → Entwickleroptionen** in der SwitchBot-App zeigen, wo Token und Client Secret liegen
2. deine Geräte abrufen und dich eins auswählen lassen
3. fragen, ob der Bot im Drücken- oder im Schalter-Modus läuft
4. die Zugangsdaten nach `~/.config/moondeck-switchbot/config` schreiben (Rechte 600)
5. das Wake-up-Skript installieren, standardmäßig nach `~/moondeck-switchbot-wol.sh`
6. auf Wunsch einen Testbefehl schicken, damit du den Bot einmal klicken hörst

## MoonDeck einrichten

In MoonDeck unter **Settings → WOL Settings**:

1. *Use custom WOL executable* einschalten
2. als Pfad das installierte Skript eintragen (standardmäßig `/home/deck/moondeck-switchbot-wol.sh`)

Der WOL-Port wird ab dann ignoriert. Der Standardpfad liegt bewusst nicht in einem versteckten Ordner — der Browse-Dialog von MoonDeck kommt in Punkt-Ordner nicht hinein.

MoonDeck ruft das Programm als `skript <HOSTNAME> <IP> <PORT> <MAC>` auf und wertet jeden Exit-Code ≠ 0 als fehlgeschlagenes Aufwecken. Die Argumente werden hier nur ins Log geschrieben; alles Nötige steht in der Konfigurationsdatei.

## Konfiguration

`~/.config/moondeck-switchbot/config` ist ein Shell-Fragment:

| Schlüssel | Bedeutung |
| --- | --- |
| `TOKEN` | SwitchBot-API-Token |
| `SECRET` | SwitchBot Client Secret |
| `DEVICE_ID` | ID des Geräts, das ausgelöst wird |
| `COMMAND` | `press` für einen Bot im Drücken-Modus, `turnOn` für Schalter-Modus oder Smart Plug |
| `COOLDOWN` | Sekunden, in denen kein zweiter Druck geschickt wird, Standard `180`, `0` schaltet ihn ab |
| `INSTALL_PATH` | Wohin das Skript installiert wurde, wird von `uninstall.sh` genutzt |

Den Cooldown gibt es, weil ein Power-Knopf kein Magic Packet ist: dasselbe Paket zweimal zu senden ist harmlos, den Knopf während des Bootens noch einmal zu drücken nicht. `install.sh` lässt sich jederzeit erneut ausführen, um etwas davon zu ändern.

## Fehlersuche

- **Die Geräteliste ist leer.** Der Bot muss mit einem Hub gekoppelt sein und die *Cloud-Dienste* müssen in der App für ihn aktiv sein.
- **Der Bot klickt, aber der PC startet nicht.** Das ist ein Montage-, kein Softwareproblem — prüfe, ob der Arm den Knopf wirklich erreicht und ob die Batterie noch was hergibt.
- **MoonDeck meldet ein fehlgeschlagenes Aufwecken.** Schau in `/tmp/moondeck-switchbot-<uid>.log`, dort landet jeder Aufruf samt roher API-Antwort. Du kannst das Skript auch von Hand mit `--test` starten.
- **MoonDeck gibt auf, bevor der PC gebootet hat.** Dreh die Timeouts in den Buddy- und Runner-Settings hoch. Ein Kaltstart dauert deutlich länger als das Aufwachen aus dem Standby, und die Standardwerte sind auf Letzteres ausgelegt.
- **Beim zweiten Versuch passiert nichts.** Das ist der Cooldown. Setz `COOLDOWN` herunter oder auf `0`, wenn wirklich jeder Versuch drücken soll.

## Deinstallation

```bash
./uninstall.sh
```

Entfernt das Skript und fragt, ob die gespeicherten Zugangsdaten mit weg sollen. Denk daran, *Use custom WOL executable* in MoonDeck wieder auszuschalten.

## Lizenz

BSD 3-Clause, siehe [LICENSE](LICENSE).
