#!/bin/bash
# Neuen Build für TestFlight bauen und hochladen: Build-Nummer +1, Archiv, Upload.
# Aufruf im Repo-Wurzelverzeichnis: Helper/homelab/testflight.sh
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Anmeldung über den App-Store-Connect-API-Schlüssel (läuft nicht ab), sonst über das Xcode-Konto
AUTH=()
if [ -f Helper/homelab/asc.env ]; then
  source Helper/homelab/asc.env
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi
P=Amperfy.xcodeproj/project.pbxproj
alt=$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*' "$P" | grep -o '[0-9]*$')
neu=$((alt + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = $alt;/CURRENT_PROJECT_VERSION = $neu;/g" "$P"
echo "Build $neu"
xcodebuild -project Amperfy.xcodeproj -scheme Amperfy -destination "generic/platform=iOS" \
  -archivePath .build-dd/HomeLabMusic.xcarchive -derivedDataPath .build-dd \
  -skipPackagePluginValidation -skipMacroValidation -allowProvisioningUpdates "${AUTH[@]}" -quiet archive
log=$(mktemp)
if ! xcodebuild -exportArchive -archivePath .build-dd/HomeLabMusic.xcarchive \
  -exportOptionsPlist Helper/homelab/ExportOptions.plist -exportPath .build-dd/export -allowProvisioningUpdates "${AUTH[@]}" >"$log" 2>&1 \
  || ! grep -q "Upload succeeded" "$log"; then
  grep -iE "error|fail" "$log" | head -5
  git checkout -- "$P"                                  # Build-Nummer zurück, nichts committen
  echo "UPLOAD FEHLGESCHLAGEN (Build $neu). Prüfen: Helper/homelab/asc.env und AuthKey-Datei, sonst Xcode → Einstellungen → Accounts."
  exit 1
fi
git commit -q -m "TestFlight: Build $neu" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" "$P" && echo "Build $neu hochgeladen und committet"
