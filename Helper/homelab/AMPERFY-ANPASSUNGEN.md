# HomeLabMusic: Anpassungen am Amperfy-Code

HomeLabMusic ist eine Kopie von [Amperfy](https://github.com/BLeeEZ/amperfy) (GPL-3), Basis **v2.1.1**.
Fast alles Eigene liegt in **eigenen Dateien**, die Amperfy nie anfasst:

- `Amperfy/HomeLab/` – Entdecken-Tab, Player-Anbindung, Shazam, Radio, Benachrichtigungen, Menü-Einträge, Startbild
- `Helper/homelab/` – Hilfsskripte (Dateien ins Projekt eintragen, Symbol zeichnen, TestFlight-Upload)

Im Amperfy-Code selbst gibt es nur die folgenden Eingriffe. Beim Übernehmen einer neuen Amperfy-Version
(`git fetch upstream --tags`, neuen Release-Tag in den Zweig `homelabmusic` mergen) genau diese Stellen prüfen.
Jede Code-Stelle ist mit `// HomeLabMusic` markiert (`git grep -n "HomeLabMusic" -- Amperfy AmperfyKit`).

## Einhängepunkte im Code (je 1 bis wenige Zeilen)

| Datei | Was | Warum |
|---|---|---|
| `Amperfy/Screens/ViewController/TabBarVC.swift` | `fixTabs.append(HLTab.erstellen(account:))` | Tab «Entdecken» |
| `Amperfy/SceneDelegate.swift` | `HLSplash.zeigen(in: window)` | Startbild kurz stehen lassen |
| `Amperfy/Screens/ViewController/EntityPreviewVC.swift` | `menuActions.append(contentsOf: HLMenue.aktionen(…))` nach den Abspiel-Befehlen | «Klingt ähnlich» und «Nicht mein Ding» in jedem Song-Menü |
| `Amperfy/AppDelegateNotificationExtensions.swift` | `if HLBenachrichtigung.behandeln(userInfo) { return }` | Antippen von «Dein Wunsch ist da» spielt den Song |
| `Amperfy/AppDelegate.swift` (`performBackgroundFetchTask`) | `await HLBenachrichtigung.pruefen()` | gelieferte Wünsche auch im Hintergrund melden |
| `Amperfy/Screens/ViewController/LoginVC.swift` | Titel «HomeLabMusic», Server-Adresse vorausgefüllt | Anmeldung für die Familie |
| `AmperfyKit/Screens/EntityImageView.swift` | `playlistCover`-Haken (Playlist-ID → Bild) | eigene Playlist-Cover von Navidrome statt Mosaik |
| `AmperfyKit/Storage/LibraryStorage.swift` | `createRadio` / `deleteRadio` auf `public` | Vorschauen als versteckte Radio-Einträge im Player |

## Projekt und Ressourcen

| Datei | Was |
|---|---|
| `Amperfy.xcodeproj/project.pbxproj` | Bundle-ID `ch.gerber.homelabmusic`, Team `C4LESUKP6H`, Version, eigene Dateien (Gruppe «HomeLab»). Konflikte hier entstehen am ehesten; eigene Dateien mit `python3 Helper/homelab/add_files.py` neu eintragen |
| `Amperfy/Info.plist` | Anzeigename, Mikrofon-Text (Shazam), `ITSAppUsesNonExemptEncryption = false` |
| `Amperfy/Amperfy.entitlements` | CarPlay bis zur Freigabe für diese App entfernt |
| `Amperfy/Screens/LaunchScreen.storyboard` | Startbild `HLStart` bildschirmfüllend |
| `AmperfyKit/Assets/AmperfyAppIcon.icon/` | App-Symbol (HLM) |
| `AmperfyKit/Assets/Assets.xcassets/Icon-monocolor.imageset/` | HLM-Zeichen (Anmeldeseite) |
| `AmperfyKit/Assets/Assets.xcassets/HLStart.imageset/` | Startbild |

## Nach einem Amperfy-Update prüfen

1. Bauen (`xcodebuild … build`), Konflikte in der Projektdatei lösen.
2. Im Simulator: Tab «Entdecken» da, Startbild, Anmeldeseite, Song-Menü mit «HomeLabMusic»-Abschnitt,
   Playlist-Cover, Vorschau im Player (Sender starten), Shazam-Knopf.
3. `Helper/homelab/testflight.sh` für den Upload.
