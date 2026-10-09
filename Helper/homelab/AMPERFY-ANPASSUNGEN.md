# HomeLabMusic: Anpassungen am Amperfy-Code

HomeLabMusic ist eine Kopie von [Amperfy](https://github.com/BLeeEZ/amperfy) (GPL-3), Basis **v2.1.1**.
Fast alles Eigene liegt in **eigenen Dateien**, die Amperfy nie anfasst:

- `Amperfy/HomeLab/` – Entdecken-Tab, Player-Anbindung, CarPlay-Bilder, lernender Mix, Shazam, Radio, Benachrichtigungen, Menü-Einträge, Startbild
- `Helper/homelab/` – Hilfsskripte (Dateien ins Projekt eintragen, Symbol zeichnen, TestFlight-Upload)

Im Amperfy-Code selbst gibt es nur die folgenden Eingriffe. Beim Übernehmen einer neuen Amperfy-Version
(`git fetch upstream --tags`, neuen Release-Tag in den Zweig `homelabmusic` mergen) genau diese Stellen prüfen.
Jede Code-Stelle ist mit `// HomeLabMusic` markiert (`git grep -n "HomeLabMusic" -- Amperfy AmperfyKit`).

## Einhängepunkte im Code (je 1 bis wenige Zeilen)

| Datei | Was | Warum |
|---|---|---|
| `Amperfy/Screens/ViewController/TabBarVC.swift` | `fixTabs.append(HLTab.erstellen(account:))` | Tab «Entdecken» |
| `Amperfy/Screens/ViewController/LibraryNavigatorConfigurator.swift` | `TabNavigatorItem.entdecken` (Titel, Symbol, `HLTab.ansicht()`) | Mac: «Entdecken» in der Seitenleiste |
| `Amperfy/Screens/ViewController/SideBarVC.swift` | Eintrag «Entdecken» nach «Home» | Mac-Seitenleiste |
| `Amperfy/Screens/ViewController/SplitVC.swift` | `HLTab.einrichten(account:)` in `viewDidLoad` | Mac nutzt SplitVC statt TabBarVC |
| `Amperfy/Screens/ViewController/TabBarVC.swift` (`pushTabCategory`) | `case .entdecken: break` | Switch vollständig |
| `Amperfy/SceneDelegate.swift` | `HLSplash.zeigen(in: window)` | Startbild kurz stehen lassen |
| `Amperfy/Screens/ViewController/EntityPreviewVC.swift` | `menuActions.append(contentsOf: HLMenue.aktionen(…))` nach den Abspiel-Befehlen | «Mix ab diesem Song» (Untermenü Nur Bibliothek / Etwas / Viel Neues) und «Nicht mein Ding» in jedem Song-Menü |
| `Amperfy/Screens/ViewController/EntityPreviewVC.swift` | `if isInstantMix, !HLMenue.ersetztInstantMix` | Amperfys «Instant Mix» ausgeblendet; unser Mix nutzt ihn intern als Ersatz, wenn der Musikwunsch-Dienst nicht antwortet |
| `Amperfy/AppDelegateNotificationExtensions.swift` | `if HLBenachrichtigung.behandeln(userInfo) { return }` | Antippen von «Dein Wunsch ist da» spielt den Song |
| `Amperfy/AppDelegate.swift` (`performBackgroundFetchTask`) | `await HLBenachrichtigung.pruefen()` | gelieferte Wünsche auch im Hintergrund melden |
| `Amperfy/Screens/ViewController/LoginVC.swift` | Titel «HomeLabMusic», Server-Adresse vorausgefüllt | Anmeldung für die Familie |
| `AmperfyKit/Screens/EntityImageView.swift` | `playlistCover`-Haken (Playlist-ID → Bild) | eigene Playlist-Cover von Navidrome statt Mosaik |
| `AmperfyKit/Storage/LibraryStorage.swift` | `createRadio` / `deleteRadio` auf `public` | Vorschauen als versteckte Radio-Einträge im Player |
| `Amperfy/Screens/Player/PlayerUIHandler.swift` | Vorschau-Titel/Untertitel | «Vorschau · Künstler» |
| `AmperfyKit/Screens/LibraryEntityImage.swift` | `vorschauInfo` / `vorschauBild` / `vorschauBildSofort` | Cover der Vorschau bzw. bei echten Radiosendern das Cover des laufenden Songs (sonst Senderbild aus Navidrome) statt Radio-Symbol |
| `AmperfyKit/Player/NowPlayingInfoCenterHandler.swift` | Vorschau-Titel, Cover (auch Radio-Cover) | Sperrbildschirm |
| `Amperfy/CarPlay/CarPlayHomeTabExtension.swift`, `CarPlayCommonListExtension.swift`, `CarPlaySceneDelegate.swift` (5 Stellen) | `HLCarPlay.nachladen(…)` nach dem Anlegen eines Eintrags | Playlist-Cover und Senderbilder auch in CarPlay |
| `Amperfy/Screens/Player/PopupPlayer+Visuals.swift`, `PopupPlayerVC.swift` | Herz-Knopf wird bei Vorschauen zu «+» (Hinzufügen) | im Player direkt zur Bibliothek hinzufügen |

**Bewusst nicht angepasst (seit 04.10.2026):** Amperfys Wiedergabe-Kern (`AudioPlayer`, `PlayerFacade`,
`RemoteCommandCenterHandler`, Zeitleiste). Vorschauen bleiben dort technisch Radios: 30 s, «LIVE», Stopp statt
Pause, kein Spulen. Ein Versuch, sie wie Songs zu behandeln (Build 15–17), machte die Wiedergabe unzuverlässig.

## Projekt und Ressourcen

| Datei | Was |
|---|---|
| `Amperfy.xcodeproj/project.pbxproj` | Bundle-ID `ch.gerber.homelabmusic`, Team `C4LESUKP6H`, Version, eigene Dateien (Gruppe «HomeLab»). Konflikte hier entstehen am ehesten; eigene Dateien mit `python3 Helper/homelab/add_files.py` neu eintragen |
| `Amperfy/Amperfy.entitlements` | `com.apple.security.device.audio-input` (Mikrofon für Shazam auf dem Mac) |
| `Amperfy/Info.plist` | Anzeigename, Mikrofon-Text (Shazam), `ITSAppUsesNonExemptEncryption = false` |
| `Amperfy/Screens/LaunchScreen.storyboard` | Startbild `HLStart` bildschirmfüllend |
| `AmperfyKit/Assets/AmperfyAppIcon.icon/` | App-Symbol (HLM) |
| `AmperfyKit/Assets/Assets.xcassets/Icon-monocolor.imageset/` | HLM-Zeichen (Anmeldeseite) |
| `AmperfyKit/Assets/Assets.xcassets/HLStart.imageset/` | Startbild |

## Nach einem Amperfy-Update prüfen

1. Bauen (`xcodebuild … build`), Konflikte in der Projektdatei lösen.
2. Im Simulator: Tab «Entdecken» da, Startbild, Anmeldeseite, Song-Menü mit «HomeLabMusic»-Abschnitt,
   Playlist-Cover, «Mix ab diesem Song» (lädt nach 10 Songs nach), Shazam-Knopf.
3. Mac-Version (Mac Catalyst) bauen: Seitenleiste mit «Entdecken».
4. `Helper/homelab/testflight.sh` für den Upload (iPhone und Mac; nur eines: `… ios` bzw. `… mac`).
