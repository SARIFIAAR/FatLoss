#!/bin/sh
# Archive the app for App Store distribution, export the IPA and upload it to TestFlight.
# Run from anywhere:  sh ~/Developer/FatLossCoach/scripts/ship.sh
set -e
cd "$(dirname "$0")/.."

KEY_ID=F32V65ACX6
ISSUER=60384b84-0407-4489-bb63-c2c1b708e376
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION" FatLossCoach.xcodeproj/project.pbxproj | tr -dc '0-9')

echo "== Archiving build $BUILD"
rm -rf build/FatLossCoach.xcarchive build/export
xcodebuild -project FatLossCoach.xcodeproj -scheme FatLossCoach -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/FatLossCoach.xcarchive \
  -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER" archive \
  2>&1 | tee "build/archive$BUILD.log" | grep -E "error:|\*\* ARCHIVE"

echo "== Exporting IPA"
xcodebuild -exportArchive \
  -archivePath build/FatLossCoach.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER" 2>&1 | tee build/export.log | grep -E "error|EXPORT SUCCEEDED|EXPORT FAILED"

IPA=$(ls build/export/*.ipa | head -1)
echo "== Uploading $IPA"
xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$KEY_ID" --apiIssuer "$ISSUER" 2>&1 | tee build/upload.log | tail -6
