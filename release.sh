#!/bin/zsh
# Archive + upload a build to App Store Connect (2026-11-01, build 4 = first Xcode 27 build: iPhone Duo + 40% launch codes).
#   ./release.sh            ? archive (Release, automatic signing) ? export with destination=upload (build/release/export.plist)
# Bump CURRENT_PROJECT_VERSION in project.yml AND the .pbxproj first. Uses the App Store Connect API key from asc/asc.mjs,
# so no Apple ID sign-in is needed. Afterwards: wait for processing, then attach the build to version 1.0 (asc/attach-build.mjs).
set -euo pipefail
cd "$(dirname "$0")"
# UPLOAD_ONLY=1 ./release.sh ? skip the archive, upload build/release/SoccerMax.xcarchive as it is
v=$(defaults read /Applications/Xcode.app/Contents/Info CFBundleShortVersionString)
[[ $v == 27* ]] || { echo "Xcode is $v ? iPhone Duo full screen needs Xcode 27.1+"; exit 1; }
KID=B8B72B9R2P
ISS=$(sed -nE "s/^const ISS = '([^']+)'.*/\1/p" asc/asc.mjs)
KEY=~/.appstoreconnect/private_keys/AuthKey_$KID.p8
AUTH=(-allowProvisioningUpdates -authenticationKeyPath $KEY -authenticationKeyID $KID -authenticationKeyIssuerID $ISS)
build=$(sed -nE 's/.*CURRENT_PROJECT_VERSION: "([0-9]+)".*/\1/p' project.yml | head -1)
if [[ -z ${UPLOAD_ONLY:-} ]]; then
echo "archiving 1.0 ($build) with Xcode $v?"
rm -rf build/release/SoccerMax-new.xcarchive
xcodebuild -project SoccerMax.xcodeproj -scheme SoccerMax -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/release/SoccerMax-new.xcarchive archive "${AUTH[@]}" -quiet
[[ -d build/release/SoccerMax-new.xcarchive ]] || { echo "archive failed"; exit 1; }
rm -rf build/release/SoccerMax-prev.xcarchive; mv build/release/SoccerMax.xcarchive build/release/SoccerMax-prev.xcarchive 2>/dev/null || true
mv build/release/SoccerMax-new.xcarchive build/release/SoccerMax.xcarchive
fi
key=$(/usr/libexec/PlistBuddy -c "Print :REVENUECAT_API_KEY" build/release/SoccerMax.xcarchive/Products/Applications/SoccerMax.app/Info.plist)
[[ $key == appl_* ]] || { echo "REVENUECAT key in the archive is not appl_ ? stop"; exit 1; }
echo "uploading?"
xcodebuild -exportArchive -archivePath build/release/SoccerMax.xcarchive -exportOptionsPlist build/release/export.plist \
  -exportPath build/release/export "${AUTH[@]}"
echo "uploaded 1.0 ($build) ? processing on Apple's side takes ~10?30 min"
