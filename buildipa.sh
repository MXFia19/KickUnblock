#!/bin/bash
# IPA non signée (comme celle de TwitchUnblock) : installée par AltStore,
# SideStore, Feather… qui la signent sur l'appareil.

set -e

cd "$(dirname "$0")"

WORKING_LOCATION="$(pwd)"
APPLICATION_NAME=KickUnblock
SCHEME_NAME=KickUnblock

mkdir -p build
cd build

echo "--- Building $APPLICATION_NAME for iOS ---"
xcodebuild -project "$WORKING_LOCATION/$APPLICATION_NAME.xcodeproj" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -derivedDataPath "$WORKING_LOCATION/build/DerivedDataApp" \
  -destination 'generic/platform=iOS' \
  clean build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED="NO"

DD_APP_PATH="$WORKING_LOCATION/build/DerivedDataApp/Build/Products/Release-iphoneos/$APPLICATION_NAME.app"
TARGET_APP="$WORKING_LOCATION/build/$APPLICATION_NAME.app"

if [ ! -d "$DD_APP_PATH" ]; then
  echo "Error: Build failed, .app not found at $DD_APP_PATH"
  exit 1
fi

rm -rf "$TARGET_APP" Payload "$APPLICATION_NAME.ipa"
cp -r "$DD_APP_PATH" "$TARGET_APP"

echo "--- Removing code signature ---"
codesign --remove "$TARGET_APP" || true
rm -rf "$TARGET_APP/_CodeSignature" "$TARGET_APP/embedded.mobileprovision"

echo "--- Packaging IPA ---"
mkdir -p Payload
cp -r "$APPLICATION_NAME.app" "Payload/$APPLICATION_NAME.app"
strip "Payload/$APPLICATION_NAME.app/$APPLICATION_NAME"
zip -qry "$APPLICATION_NAME.ipa" Payload
rm -rf "$APPLICATION_NAME.app" Payload

echo "--- Success: build/$APPLICATION_NAME.ipa created ---"
