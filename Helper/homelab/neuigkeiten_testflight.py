#!/usr/bin/env python3
"""Neuesten Eintrag aus der Neuigkeiten-Datei als TestFlight-Text («Was testen») zum Build setzen.
Gleiche Datei in allen HomeLab-Apps. Der Build erscheint erst einige Minuten nach dem Upload, darum wird gewartet.
Aufruf: neuigkeiten_testflight.py <Datei> <Bundle-ID> <Build> <IOS|MAC_OS|TV_OS> [--pruefen]
--pruefen zeigt nur den Text und die Sprachen der App, schreibt nichts.
Schlüssel aus der Umgebung: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH."""
import json, os, re, sys, time, urllib.error, urllib.parse, urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
WARTEN_MINUTEN = 20


def text_aus(pfad):
    """Oberster Eintrag ohne Markdown-Zeichen; die App zeigt dieselbe Datei."""
    zeilen, drin = [], False
    for zeile in open(pfad, encoding="utf-8"):
        zeile = zeile.rstrip()
        if zeile.startswith("## "):
            if drin:
                break
            drin = True
        elif drin and zeile.startswith("### "):
            zeilen += ["", zeile[4:]]
        elif drin and zeile.startswith("- "):
            zeilen.append(zeile)
    text = "\n".join(zeilen).strip()
    if not text:
        sys.exit(f"Kein Eintrag in {pfad}")
    return text[:4000]


def anfrage(pfad, methode="GET", inhalt=None):
    jetzt = int(time.time())
    token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": jetzt, "exp": jetzt + 600, "aud": "appstoreconnect-v1"},
                       open(os.path.expanduser(os.environ["ASC_KEY_PATH"])).read(), algorithm="ES256",
                       headers={"kid": os.environ["ASC_KEY_ID"]})
    req = urllib.request.Request(API + pfad, method=methode, data=json.dumps(inhalt).encode() if inhalt else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as antwort:
        return json.load(antwort)


def setzen(build_id, sprachen, text):
    vorhanden = {x["attributes"]["locale"]: x["id"]
                 for x in anfrage(f"/builds/{build_id}/betaBuildLocalizations")["data"]}
    for sprache in sprachen:
        attribute = {"whatsNew": text}
        if sprache in vorhanden:
            anfrage(f"/betaBuildLocalizations/{vorhanden[sprache]}", "PATCH",
                    {"data": {"type": "betaBuildLocalizations", "id": vorhanden[sprache], "attributes": attribute}})
        else:
            anfrage("/betaBuildLocalizations", "POST",
                    {"data": {"type": "betaBuildLocalizations", "attributes": {**attribute, "locale": sprache},
                              "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})


def main():
    argumente = [a for a in sys.argv[1:] if a != "--pruefen"]
    if len(argumente) != 4:
        sys.exit(__doc__)
    datei, bundle, build, plattform = argumente
    text = text_aus(datei)
    print(f"TestFlight-Text:\n{text}\n")
    q = urllib.parse.urlencode({"filter[bundleId]": bundle})
    app = anfrage(f"/apps?{q}")["data"][0]
    # de-DE für Schweizer und deutsche Geräte, dazu die Hauptsprache der App als Rückfall
    sprachen = list(dict.fromkeys(["de-DE", app["attributes"]["primaryLocale"]]))
    if "--pruefen" in sys.argv:
        print(f"App {app['id']} ({bundle}), Sprachen {sprachen}: nichts geschrieben.")
        return
    q = urllib.parse.urlencode({"filter[app]": app["id"], "filter[version]": build,
                                "filter[preReleaseVersion.platform]": plattform, "limit": 1})
    ende = time.time() + WARTEN_MINUTEN * 60
    while True:
        gefunden = anfrage(f"/builds?{q}")["data"]
        if gefunden:
            break
        if time.time() > ende:
            sys.exit(f"Build {build} ({plattform}) nach {WARTEN_MINUTEN} Minuten nicht sichtbar. Text nicht gesetzt.")
        time.sleep(30)
    setzen(gefunden[0]["id"], sprachen, text)
    print(f"TestFlight-Text gesetzt: Build {build} ({plattform}), {sprachen}")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as fehler:
        sys.exit(f"App Store Connect: {fehler.code} {fehler.read().decode()[:400]}")
