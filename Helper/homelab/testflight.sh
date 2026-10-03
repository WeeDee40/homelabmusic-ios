#!/bin/bash
# Neuen Build für TestFlight bauen und hochladen: Build-Nummer +1, Archiv, Upload.
# Aufruf im Repo-Wurzelverzeichnis: Helper/homelab/testflight.sh
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
P=Amperfy.xcodeproj/project.pbxproj
alt=$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*' "$P" | grep -o '[0-9]*$')
neu=$((alt + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = $alt;/CURRENT_PROJECT_VERSION = $neu;/g" "$P"
echo "Build $neu"
xcodebuild -project Amperfy.xcodeproj -scheme Amperfy -destination "generic/platform=iOS" \
  -archivePath .build-dd/HomeLabMusic.xcarchive -derivedDataPath .build-dd \
  -skipPackagePluginValidation -skipMacroValidation -allowProvisioningUpdates -quiet archive
xcodebuild -exportArchive -archivePath .build-dd/HomeLabMusic.xcarchive \
  -exportOptionsPlist Helper/homelab/ExportOptions.plist -exportPath .build-dd/export -allowProvisioningUpdates \
  | grep -E "Upload|error" || true
git commit -q -m "TestFlight: Build $neu" "$P" && echo "Build $neu hochgeladen und committet"
