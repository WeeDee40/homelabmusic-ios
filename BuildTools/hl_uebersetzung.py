#!/usr/bin/env python3
"""HomeLabMusic: deutsche Oberfläche.

DE / PLURAL / FORMAT sind die Quelle der Übersetzungen; `python3 BuildTools/hl_uebersetzung.py katalog` schreibt daraus
Amperfy/Localizable.xcstrings (nicht von Hand oder in Xcode ändern, sonst überschreibt es der nächste Lauf).
`markieren` wurde einmal am 16.11.2026 über die sichtbaren Bildschirme laufen gelassen (String(localized:) um die Texte);
nur für neue Dateien erneut verwenden und das Ergebnis prüfen.
"""
import json, re, sys, pathlib

ROOT = pathlib.Path.home() / "homelabmusic-ios"

DE = {
    # Bibliothek, Tabs, Startseite
    "Library": "Bibliothek", "Home": "Start", "Search": "Suche", "Settings": "Einstellungen",
    "Artists": "Künstler", "Albums": "Alben", "Songs": "Songs", "Genres": "Genres",
    "Directories": "Ordner", "Playlists": "Playlists", "Podcasts": "Podcasts", "Downloads": "Downloads",
    "Favorite Songs": "Lieblingssongs", "Favorite Albums": "Lieblingsalben", "Favorite Artists": "Lieblingskünstler",
    "Newest Albums": "Zuletzt hinzugefügt", "Recently Played Albums": "Zuletzt gespielt", "Radios": "Radiosender",
    "Random Albums": "Zufällige Alben", "Recently Played Playlists": "Zuletzt gespielte Playlists",
    "Newest Podcast Episodes": "Neueste Podcast-Folgen", "Random Artists": "Zufällige Künstler",
    "Random Genres": "Zufällige Genres", "Random Songs": "Zufällige Songs", "Album Artists": "Album-Künstler",
    "Queue": "Warteschlange", "Edit": "Bearbeiten", "Done": "Fertig", "Refresh Randoms": "Zufällige neu mischen",
    "Home Preferences": "Startseite anpassen", "Visible": "Sichtbar", "Hidden": "Ausgeblendet",
    "Offline Mode is active.": "Der Offline-Modus ist eingeschaltet.", "Reminder": "Hinweis",
    # Kontextmenü
    "Play": "Wiedergeben", "Shuffle": "Zufällig", "Random": "Zufällig", "Instant Mix": "Sofort-Mix",
    "No similar songs found": "Keine ähnlichen Songs gefunden",
    "Music Queue": "Warteschlange", "Insert Context Queue": "Im Kontext als Nächstes",
    "Append Context Queue": "Im Kontext ans Ende", "Insert User Queue": "Als Nächstes spielen",
    "Append User Queue": "Zuletzt spielen", "Insert Podcast Queue": "Als nächste Folge",
    "Append Podcast Queue": "Folge ans Ende",
    "Unmark favorite": "Kein Liebling mehr", "Favorite": "Als Liebling markieren", "Not rated": "Nicht bewertet",
    "No Rating": "Keine Bewertung", "Add to Playlist": "Zu Playlist hinzufügen", "Show Album": "Album zeigen",
    "Show Artist": "Künstler zeigen", "Show Podcast": "Podcast zeigen", "Download": "Laden",
    "Delete Cache": "Vom Gerät löschen", "Delete": "Löschen", "Cancel": "Abbrechen",
    "Delete on Server": "Auf dem Server löschen",
    "Are you sure to delete the podcast episode on the server?": "Die Folge wirklich auf dem Server löschen?",
    "Share": "Teilen", "Go to Site": "Webseite öffnen", "Show Podcast Description": "Beschreibung zeigen",
    "Song Info": "Song-Infos",
    # Listen: Filter, Sortierung, Leere
    "All": "Alle", "Cached": "Auf dem Gerät", "User": "Eigene", "Smart": "Smart",
    "Name": "Name", "Rating": "Bewertung", "Artist": "Künstler", "Duration": "Dauer", "Year": "Jahr",
    "Sort": "Sortieren", "Table": "Liste", "Grid": "Raster", "Change Grid Size": "Rastergrösse ändern",
    "Style": "Darstellung", "Filter": "Filter", "Starred date": "Liebling seit", "Date Added": "Hinzugefügt am",
    "Last time played": "Zuletzt gespielt", "Change date": "Geändert am", "Options": "Optionen",
    "Many Songs": "Viele Songs", "OK": "OK",
    "No Songs": "Keine Songs", "Your songs will appear here.": "Hier erscheinen deine Songs.",
    "No Playlists": "Keine Playlists", "Your playlists will appear here.": "Hier erscheinen deine Playlists.",
    "No Genres": "Keine Genres", "Your genres will appear here.": "Hier erscheinen die Genres.",
    "Sync All Playlists": "Alle Playlists abgleichen", "All playlists have been synced.": "Alle Playlists sind abgeglichen.",
    "Albums and Songs": "Alben und Songs", "Artists, Albums and Songs": "Künstler, Alben und Songs",
    "Directories and Songs": "Ordner und Songs",
    "Clear finished downloads": "Fertige Downloads entfernen", "Retry failed downloads": "Fehlgeschlagene erneut laden",
    "Cancel all downloads": "Alle Downloads abbrechen",
    # Playlist hinzufügen
    "Select": "Auswählen", "Some Songs are already in this Playlist.": "Einige Songs sind schon in dieser Playlist.",
    "Add Duplicates": "Doppelte hinzufügen", "Skip Duplicates": "Doppelte weglassen",
    "This Song is already in your Playlist.": "Dieser Song ist schon in deiner Playlist.",
    "Some Songs are already in your Playlist.": "Einige Songs sind schon in deiner Playlist.",
    "Add Duplicate": "Trotzdem hinzufügen", "Skip": "Weglassen", "Add Songs to Playlist": "Songs zur Playlist hinzufügen",
    "Add Songs Anyway": "Trotzdem hinzufügen", "Abort": "Abbrechen",
    # Player
    "Previous": "Zuvor gespielt", "Next from Queue": "Als Nächstes", "No Lyrics": "Kein Songtext",
    "Playback Rate": "Tempo", "Visualizer Style": "Visualisierung", "Clear Player": "Player leeren",
    "Clear User Queue": "Warteschlange leeren", "Show Lyrics": "Songtext zeigen", "Hide Lyrics": "Songtext ausblenden",
    "Show Audio Visualizer": "Visualisierung zeigen", "Hide Audio Visualizer": "Visualisierung ausblenden",
    "Add Context Queue to Playlist": "Wiedergabeliste zu Playlist hinzufügen",
    "Scroll to currently playing": "Zum laufenden Song", "Player Info": "Player-Infos",
    "Player Options": "Player-Optionen", "No music playing": "Keine Musik", "No podcast playing": "Kein Podcast",
    "Toggle Favorite": "Liebling umschalten", "1 Artist": "1 Künstler", "1 Episode": "1 Folge", "Not Available": "Nicht verfügbar", "Unknown": "Unbekannt", "Add Account": "Konto hinzufügen",
    "Next from:": "Als Nächstes aus:", "Clear": "Leeren", "Sleep Timer": "Einschlaf-Timer", "End of Song or Podcast Episode": "Ende des Songs oder der Folge",
    "5 Minutes": "5 Minuten", "10 Minutes": "10 Minuten", "15 Minutes": "15 Minuten", "30 Minutes": "30 Minuten",
    "45 Minutes": "45 Minuten", "1 Hour": "1 Stunde", "2 Hours": "2 Stunden", "4 Hours": "4 Stunden",
}

# Mehrzahl und Platzhalter: Schlüssel im Katalog → (en one, en other, de one, de other) bzw. (en, de)
PLURAL = {
    "%lld Songs": ("%lld Song", "%lld Songs", "%lld Song", "%lld Songs"),
    "%lld Albums": ("%lld Album", "%lld Albums", "%lld Album", "%lld Alben"),
    "%lld Artists": ("%lld Artist", "%lld Artists", "%lld Künstler", "%lld Künstler"),
    "%lld Episodes": ("%lld Episode", "%lld Episodes", "%lld Folge", "%lld Folgen"),
    "%lld Stars": ("%lld Star", "%lld Stars", "%lld Stern", "%lld Sterne"),
}
FORMAT = {
    "Turn Off (Pause at: %@)": "Ausschalten (Pause um %@)",
    "Pause at: %@": "Pause um %@",
    "Turn Off (Pause at end of %@)": "Ausschalten (Pause am Ende: %@)",
    "Pause at end of %@": "Pause am Ende: %@",
    "Year %@": "Jahr %@",
    "%@ left": "noch %@",
    "Rating: %@": "Bewertung: %@",
    "%@ Stars": "%@ Sterne",
    "No %@": "%@: noch leer",
    "Your %@ will appear here.": "Sobald es etwas gibt, erscheint es hier.",
    "Download %@": "%@ laden",
    "Search in \"%@\"": "In «%@» suchen",
    "Add %lld Songs to Playlist": "%lld Songs zur Playlist hinzufügen",
    "Are you sure to add %lld songs from \"%@\" to download queue?": "Wirklich %lld Songs aus «%@» laden?",
}

DATEIEN = sorted(set(
    list((ROOT / "Amperfy/Screens").rglob("*.swift"))
    + [ROOT / "Amperfy/LibraryDisplayType+Extension.swift",
       ROOT / "AmperfyKit/Storage/LibraryDisplaySettings.swift",
       ROOT / "AmperfyKit/Storage/HomeSection.swift"]))
SKIP_ZEILE = re.compile(r"report\(topic|logger|fatalError|os_log|identifier:|forKey|sessionRole|^\s*//|Text\(|accessibilityIdentifier|case \"")

def markieren():
    n = 0
    for f in DATEIEN:
        if not f.exists():
            continue
        alt = f.read_text()
        zeilen = alt.split("\n")
        for i, z in enumerate(zeilen):
            if SKIP_ZEILE.search(z):
                continue
            for en in DE:
                lit = '"' + en.replace('"', '\\"') + '"'
                # nur ganze Literale, nicht schon markiert, nicht Teil eines Interpolations-Literals
                muster = re.compile(r'(?<![\w\\])(?<!localized: )' + re.escape(lit) + r'(?!\w)')
                neu = muster.sub(lambda m: f"String(localized: {lit})", z)
                if neu != z:
                    n += neu.count("String(localized:") - z.count("String(localized:")
                    z = neu
            zeilen[i] = z
        neu = "\n".join(zeilen)
        if neu != alt:
            f.write_text(neu)
    print("markiert:", n)

def katalog():
    strings = {}
    for en, de in DE.items():
        strings[en] = {"localizations": {"de": {"stringUnit": {"state": "translated", "value": de}}}}
    for k, (e1, eo, d1, do) in PLURAL.items():
        def var(one, other):
            return {"variations": {"plural": {
                "one": {"stringUnit": {"state": "translated", "value": one}},
                "other": {"stringUnit": {"state": "translated", "value": other}}}}}
        strings[k] = {"localizations": {"en": var(e1, eo), "de": var(d1, do)}}
    for k, de in FORMAT.items():
        strings[k] = {"localizations": {"de": {"stringUnit": {"state": "translated", "value": de}}}}
    kat = {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}
    (ROOT / "Amperfy/Localizable.xcstrings").write_text(json.dumps(kat, ensure_ascii=False, indent=2) + "\n")
    print("Katalog:", len(strings), "Einträge")

if __name__ == "__main__":
    if "markieren" in sys.argv: markieren()
    if "katalog" in sys.argv: katalog()
