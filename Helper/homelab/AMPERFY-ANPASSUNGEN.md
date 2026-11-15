# HomeLabMusic: Anpassungen am Amperfy-Code

HomeLabMusic ist eine Kopie von [Amperfy](https://github.com/BLeeEZ/amperfy) (GPL-3), Basis **v2.1.1**.
Fast alles Eigene liegt in **eigenen Dateien**, die Amperfy nie anfasst:

- `Amperfy/HomeLab/` – Entdecken-Tab, Player-Anbindung, CarPlay-Bilder, lernender Mix, Shazam, Radio, Benachrichtigungen, Menü-Einträge, Startbild, Stöbern-Kacheln der Suche (`HLSuche.swift`), Anmeldung mit Pocket ID (`HLPocketID.swift`: Ablauf, Widerruf erkennen, Abmelden), Wunsch-Knopf im Mini-Player (`HLMiniKnopf.swift`), Entdecken-Block der Künstlerseite (`HLKuenstlerBlock.swift`), Speichergrenze für Songs und Cover (`HLSpeicher.swift`), Mediathek pro Person (`HLMediathek.swift`: versteckte Navidrome-Playlist, Markierungen in Core Data; `HLListenFilter.swift`: was die Listen zeigen; `HLMediathekUI.swift`: Menüeinträge und «+»)
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
| `Amperfy/Screens/ViewController/EntityPreviewVC.swift` | `if isInstantMix, !HLMenue.ersetztInstantMix` | Amperfys «Instant Mix» ausgeblendet; unser Mix nutzt ihn intern als Ersatz, wenn der Medienwunsch-Dienst nicht antwortet |
| `Amperfy/AppDelegateNotificationExtensions.swift` | `if HLBenachrichtigung.behandeln(userInfo) { return }` | Antippen von «Dein Wunsch ist da» spielt den Song |
| `Amperfy/AppDelegate.swift` (`performBackgroundFetchTask`) | `await HLBenachrichtigung.pruefen()` | gelieferte Wünsche auch im Hintergrund melden |
| `Amperfy/Screens/ViewController/LoginVC.swift` | Titel «HomeLabMusic», Server-Adresse vorausgefüllt | Anmeldung für die Familie |
| `Amperfy/Screens/ViewController/LoginVC.swift` (Pocket ID) | Knopf «Mit Pocket ID anmelden» unter «Login» (`pocketIDPressed` → `HLPocketID.anmelden`); `login()` aufgeteilt in Prüfung und `login(credentials:apiType:)`; `showErrorMsg` mit Titel und OK-Aktion; beim Vorausfüllen nie die Kopfzeile `x-homelab-geraet` übernehmen | Anmeldung über den Einrichtungsdienst (Gerätetoken als eigene Kopfzeile, Caddy setzt `Remote-User`). Ohne den Filter würde eine Passwort-Anmeldung das Token des aktiven Kontos mitschicken und als diese Person angemeldet |
| `Amperfy/SwiftUI/Settings/Account/AccountSettingsView.swift` | `HLPocketID.abmelden` am Anfang von `logout`; bei Pocket-ID-Konten «Mit Pocket ID neu anmelden» statt «Update Password» | Gerät beim Dienst entfernen; nach einem Widerruf neues Token holen |
| `AmperfyKit/Screens/EntityImageView.swift` | `playlistCover`-Haken (Playlist-ID → Bild) | eigene Playlist-Cover von Navidrome statt Mosaik |
| `AmperfyKit/Storage/LibraryStorage.swift` | `createRadio` / `deleteRadio` / `createSong` auf `public` | Vorschauen als versteckte Radio-Einträge im Player; frisch gelieferte Songs gezielt nachladen |
| `Amperfy/Screens/Player/PlayerUIHandler.swift` | Vorschau-Titel/Untertitel | «Vorschau · Künstler» |
| `AmperfyKit/Screens/LibraryEntityImage.swift` | `vorschauInfo` / `vorschauBild` / `vorschauBildSofort` | Cover der Vorschau bzw. bei echten Radiosendern das Cover des laufenden Songs (sonst Senderbild aus Navidrome) statt Radio-Symbol |
| `AmperfyKit/Player/NowPlayingInfoCenterHandler.swift` | Vorschau-Titel, Cover (auch Radio-Cover) | Sperrbildschirm |
| `Amperfy/CarPlay/CarPlayHomeTabExtension.swift`, `CarPlayCommonListExtension.swift`, `CarPlaySceneDelegate.swift` (5 Stellen) | `HLCarPlay.nachladen(…)` nach dem Anlegen eines Eintrags | Playlist-Cover und Senderbilder auch in CarPlay |
| `AmperfyKit/Storage/ResultController/BasicFetchedResultsController.swift` | `hlListenFilter` (Entität, Amperfys Prädikat, «aus der Suche») + `hlListenSortierung` + `hlFilterStand`, `hlBibliotheksPraedikat`; in `NSFetchedResultsController.fetch()` ein Aufruf `hlVorDemLaden` (Prädikat und Sortierung, Cache verwerfen bei Änderung) | alle Listen zentral filtern; die Entscheidung liegt in `Amperfy/HomeLab/HLListenFilter.swift` (Bibliothek Mediathek/Kinder, Mediathek pro Person, fremde und Mediathek-Playlist ausblenden, «Newest Albums» = zuletzt in die Mediathek gekommen) |
| `AmperfyKit/Storage/LibraryStorage.swift` (7 Zeilen) | `hlBibliothekFiltern(fetchRequest)` vor Zufallsalben/-künstler/-songs, `hlBibliothekFiltern(fetchRequest, suche: true)` in der Suche (inkl. Playlists) | Startseite wie die Bibliothek; die Suche findet auch, was nicht in der Mediathek ist |
| `Amperfy/Screens/ViewController/WelcomePopupPresenter.swift` (1 Zeile), `Amperfy/SwiftUI/Settings/SettingsView.swift` | `HLNeuigkeiten` beim Start, Knopf «Neuigkeiten» | Fenster «Neu in dieser Version» nach einem Update; Text in `Amperfy/HomeLab/NEUIGKEITEN.md` |
| `Amperfy/Screens/ViewController/SearchVC.swift` | Abschnitt «Entdecken» nach Künstlern, Alben und Songs der Bibliothek, vor den Playlists (`SearchSection`-Reihenfolge, `HLSuchEinbau`); in «Alle» nur 5 Treffer je Art (`categoryItemLimitAlle`); Texte deutsch (Überschriften, «Alle / Offline», leerer Verlauf); Tastatur schliesst beim Scrollen | Bibliothek und Medienwunsch in einer Suche, wie bei HomeLabTV; Entdecken ohne langes Scrollen sichtbar; der Tab «Entdecken» hat keine eigene Suche mehr |
| `Amperfy/Screens/ViewController/SearchVC.swift` (Stöbern) | `SearchSection.Stoebern` vor dem Verlauf: bei leerer Suche Kacheln für Stimmungen und die grössten Genres (`HLSuchEinbau.stoebernZelle`); öffnet eine eigene Seite (`HLZiel.stoebern`); «Noch nichts gesucht» entfällt | wie «Alles durchsuchen» bei Spotify und Apple Music |
| `Amperfy/Screens/Player/PlayerControlView.swift` (`prepare`), `Amperfy/Screens/Player/MiniPlayerView.swift` (`trailingButtonsView`) | `HLAusgabe.shared.beobachten(airplayButton)` nach dem Einrichten des AirPlay-Knopfs | Knopf zeigt das Symbol des aktuellen Ausgabegeräts (AirPods, Kopfhörer, HomePod, Auto) in der Akzentfarbe statt immer das AirPlay-Zeichen; Logik in `HLAusgabe.swift`, nicht am Mac |
| `Amperfy/Screens/Player/MiniPlayerView.swift` (`configureForiOS`, `refreshPlayer`) | `HLMiniKnopf.einbauen(in:vor:)` vor dem Abspielknopf; Titel, Untertitel und Tippfläche enden am Knopf statt am Abspielknopf | eine Leiste für den laufenden Song: «+» bei Vorschauen, langes Drücken = Menü (Künstler, Album, Mix, Nicht mein Ding); die eigene Leiste über dem Mini-Player (`HLMiniPlayer`) ist weg |
| `Amperfy/Screens/ViewController/ArtistDetailVC.swift` (5 Zeilen) | oberster, sonst leerer Abschnitt (Index 0) zeigt `HLKuenstlerEinbau`: Mix, Folgen, «Beliebt, noch nicht bei dir», Link zur Entdecken-Seite | eine Künstlerseite wie bei Spotify; die Entdecken-Seite verlinkt zurück («n Songs in deiner Bibliothek»). Deezer-ID über api.deezer.com, nur bei gleichem Namen |
| `Amperfy/Screens/ViewController/ArtistDetailVC.swift` (`cellForRowAt`, Anfang) | Zeile ausserhalb der aktuellen Liste: leere Zelle und `reloadData()` | Absturz «no object at index 1 in section at index 0», wenn ein Abgleich die Songs ändert, während die Seite offen ist (Nov. 2026) |
| `AmperfyKit/Api/CommonLibrarySyncer.swift`, `Subsonic/SubsonicLibrarySyncer.swift`, `Ampache/AmpacheLibrarySyncer.swift` | `AlbumSyncCoalescer` – **unverändert aus Upstream übernommen** (a3011f7b, #809), ohne Test und pbxproj | gleichzeitige Album-Abgleiche legten Songs/Künstler doppelt an; beim Einspielen des nächsten Amperfy-Release einfach dessen Fassung nehmen |
| `AmperfyKit/Screens/LibraryEntityImage.swift` (`fehlendesKuenstlerBild`, `display`, `displayAndUpdate`) | Haken für Künstler ohne Bildeintrag; `displayAndUpdate` lädt beim gleichen Objekt ein inzwischen bekanntes Bild | Amperfy gibt nur Künstlern aus der ersten Vollsynchronisation ein Bild; nachgeholt in `HLCover.kuenstlerBild` (Künstlersuche, Bild doppelter Einträge teilen) |
| `AmperfyKit/Api/Subsonic/SubsonicServerApi.swift` (`generateUrl(forArtworkId:)`) | `size=1000` bei `getCoverArt` | Cover in Originalgrösse waren bis 1,8 MB; zusammen mit `HLSpeicher` (Songs 4 GB nach «zuletzt gehört», Cover 300 MB) gegen 12 GB Speicher auf einem iPhone |
| `AmperfyKit/Storage/EntityWrappers/AbstractPlayable.swift` (`imagePath`, `bildBrauchbar`, `bildDefekt`), `Amperfy/Screens/Player/PlayerUIHandler.swift` (`refreshArtwork`), `AmperfyKit/Screens/LibraryEntityImage.swift` (`downloadFinishedSuccessful`, `loadImageAndCacheIt`) | Cover-Wahl nimmt das erste lesbare von eingebettet / Song-Cover (`mf-…`) / Album-Cover (fehlende Datei oder von UIImage nicht lesbar = überspringen; steht in AbstractPlayable, weil der Player `currentlyPlaying` als AbstractPlayable gibt, ein Override in Song griff dort nie); Player ruft `HLCover.nachladen` (Song- und Album-Cover, räumt fehlgeschlagene Download-Einträge weg); Bild wird auch beim fertigen Album-Cover neu geladen | Player ohne Cover, obwohl die Übersicht (Album-Cover) eines zeigte (z. B. eingebettetes Cover eingetragen, Datei weg); Amperfy fordert Cover nur in Listen an und versucht Fehlgeschlagenes erst nach einem Kaltstart wieder |
| `AmperfyKit/Player/BackendAudioPlayer.swift` (`restartPlayer`) | alten Player vor dem Ersetzen anhalten (`delegate = nil`, `stop()`) und 3 s am Leben halten | Abstürze Build 24/25: nach einem Wiedergabefehler griffen Audio-Thread bzw. Netzwerk auf den schon freigegebenen Player zu |
| `AmperfyKit/Storage/ManagedObjects/Amperfy.xcdatamodeld/HomeLabMusic 1.xcdatamodel`, `.xccurrentversion`, `Migration/CoreDataMigrationVersion.swift` (`case hl1`, Kette `v49 → hl1`), Projektdatei (Modell in der Versionsgruppe) | eigene Modellversion «HomeLabMusic 1» = Amperfy v49 + `Song.hlInMediathek`, `Artist.hlInMediathek` (SQLite-Spalte `ZHLINMEDIATHEK1`), `Album.hlMediathekSeit` (Reihenfolge in der Mediathek als Datum, kein echtes Datum), je mit Index | Mediathek: schneller Filter, Sortierung «Neu in meiner Mediathek». **Bringt ein Amperfy-Release eine neue Modellversion (z. B. v50):** Geräte stehen auf `hl1`, nie auf v50. Neue «HomeLabMusic 2» = Upstream-v50 + diese drei Felder mit Indizes anlegen, als aktuelle Version setzen und die Kette `hl1 → hl2` eintragen (v50 bleibt im Enum, ist aber für unsere Geräte nie Zwischenschritt). Braucht Upstream für v49 → v50 eine eigene Mapping-Datei (`VersionMappings/`), dasselbe für `hl1 → hl2` anlegen. Alle bisherigen Modelle im Bundle lassen |
| `Amperfy/Screens/ViewController/LibraryNavigatorConfigurator.swift` (3 Zeilen) | `HLListenFilter.sichtbar(librarySettings.inUse)` | «Directories» im Modus Mediathek ausblenden (Ordner zeigen immer alles). Bearbeiten («Edit») in diesem Modus speichert die Liste ohne Verzeichnisse |
| `Amperfy/Screens/ViewController/CommonScreenOperations.swift` (`setupUserNavButton`) | `HLBibliothek.shared.knopfEinsetzen(in:)` | Umschalter «Mediathek ⌄ / Kinder ⌄» (Wahl pro Konto) neben dem Konto-Knopf (Home, Bibliothek, Suche) |
| `Amperfy/Screens/View/PlayableTableCell.swift` (`refresh`, letzter `else`-Zweig) | `accessoryView = HLMediathekUI.zubehoer(fuer:nachher:)` | «+» am Zeilenende für Songs, die nicht in der Mediathek sind (Album-/Künstlerseite, Suche, Favoriten, Playlists); eigene ohne Knopf. Menüeinträge «Zur Mediathek hinzufügen / Aus Mediathek entfernen» kommen ohne weiteren Eingriff über den bestehenden `HLMenue`-Haken |
| `Amperfy/Screens/Player/PopupPlayer+Visuals.swift`, `PopupPlayerVC.swift` | Herz-Knopf wird bei Vorschauen zu «+» (Hinzufügen) | im Player direkt zur Bibliothek hinzufügen |

**Bewusst nicht angepasst (seit 04.10.2026):** Amperfys Wiedergabe-Kern (`AudioPlayer`, `PlayerFacade`,
`RemoteCommandCenterHandler`, Zeitleiste). Vorschauen bleiben dort technisch Radios: 30 s, «LIVE», Stopp statt
Pause, kein Spulen. Ein Versuch, sie wie Songs zu behandeln (Build 15–17), machte die Wiedergabe unzuverlässig.

## Projekt und Ressourcen

| Datei | Was |
|---|---|
| `Amperfy.xcodeproj/project.pbxproj` | Bundle-ID `ch.gerber.homelabmusic`, Team `C4LESUKP6H`, Version, eigene Dateien (Gruppe «HomeLab»). Konflikte hier entstehen am ehesten; eigene Dateien mit `python3 Helper/homelab/add_files.py` neu eintragen |
| `Amperfy.xcodeproj/…/Package.resolved` und Projektdatei | AudioStreaming 1.4.5 statt 1.4.4 (Absturz-Fix in `DispatchTimerSource.deinit`); bei einem Amperfy-Update nicht auf eine ältere Version zurückfallen |
| `Amperfy/Amperfy.entitlements` | `com.apple.security.device.audio-input` (Mikrofon für Shazam auf dem Mac) |
| `Amperfy/Info.plist` | Anzeigename, `CFBundleName` = HomeLabMusic (statt `$(PRODUCT_NAME)` = Amperfy; erscheint im Systemdialog der Pocket-ID-Anmeldung), Mikrofon-Text (Shazam), `ITSAppUsesNonExemptEncryption = false` |
| `Amperfy/Screens/LaunchScreen.storyboard` | Startbild `HLStart` bildschirmfüllend |
| `AmperfyKit/Assets/AmperfyAppIcon.icon/` | App-Symbol (HLM) |
| `AmperfyKit/Assets/Assets.xcassets/Icon-monocolor.imageset/` | HLM-Zeichen (Anmeldeseite) |
| `AmperfyKit/Assets/Assets.xcassets/HLStart.imageset/` | Startbild |

## Nach einem Amperfy-Update prüfen

1. Bauen (`xcodebuild … build`), Konflikte in der Projektdatei lösen.
2. Im Simulator: Tab «Entdecken» da, Startbild, Anmeldeseite, Song-Menü mit «HomeLabMusic»-Abschnitt,
   Playlist-Cover, «Mix ab diesem Song» (lädt nach 10 Songs nach), Shazam-Knopf, Suche mit Abschnitt «Entdecken»,
   leere Suche mit Kacheln, Vorschau abspielen → «+» und Menü im Mini-Player, Künstlerseite der Bibliothek mit Mix/Folgen.
3. Mac-Version (Mac Catalyst) bauen: Seitenleiste mit «Entdecken».
4. `Helper/homelab/testflight.sh` für den Upload (iPhone und Mac; nur eines: `… ios` bzw. `… mac`).
