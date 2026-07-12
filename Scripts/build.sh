#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DockerBridge"
LOGIN_ITEM_NAME="DockerBridgeLoginItem"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
LOGIN_ITEM_APP_DIR="$APP_DIR/Contents/Library/LoginItems/$LOGIN_ITEM_NAME.app"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"
SWIFTPM_BUILD_DIR="$BUILD_DIR/SwiftPM"
SWIFTPM_CACHE_DIR="$BUILD_DIR/SwiftPMCache"
ARCH="$(uname -m)"

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE_DIR"
export XDG_CACHE_HOME="$SWIFTPM_CACHE_DIR"

rm -rf "$APP_DIR"
rm -rf "$BUILD_DIR/DatabaseBridge.app" "$BUILD_DIR/Database Bridge.app"
rm -rf "$MODULE_CACHE_DIR"
mkdir -p \
  "$APP_DIR/Contents/MacOS" \
  "$APP_DIR/Contents/Resources" \
  "$LOGIN_ITEM_APP_DIR/Contents/MacOS" \
  "$MODULE_CACHE_DIR" \
  "$SWIFTPM_BUILD_DIR" \
  "$SWIFTPM_CACHE_DIR"

swift build \
  --package-path "$ROOT_DIR" \
  --scratch-path "$SWIFTPM_BUILD_DIR" \
  --disable-sandbox \
  --configuration release \
  --arch "$ARCH" \
  --product "$APP_NAME" >&2

swift build \
  --package-path "$ROOT_DIR" \
  --scratch-path "$SWIFTPM_BUILD_DIR" \
  --disable-sandbox \
  --configuration release \
  --arch "$ARCH" \
  --product "$LOGIN_ITEM_NAME" >&2

cp "$SWIFTPM_BUILD_DIR/$ARCH-apple-macosx/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$SWIFTPM_BUILD_DIR/$ARCH-apple-macosx/release/$LOGIN_ITEM_NAME" "$LOGIN_ITEM_APP_DIR/Contents/MacOS/$LOGIN_ITEM_NAME"
cp "$ROOT_DIR/Resources/LoginItem-Info.plist" "$LOGIN_ITEM_APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/PkgInfo" "$LOGIN_ITEM_APP_DIR/Contents/PkgInfo"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DockerBridgeBuildDate string $(date +%Y-%m-%d)" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/PkgInfo" "$APP_DIR/Contents/PkgInfo"
cp "$ROOT_DIR/Resources/DockerBridge.icns" "$APP_DIR/Contents/Resources/DockerBridge.icns"
cp "$ROOT_DIR/LICENSE" "$APP_DIR/Contents/Resources/DockerBridge-LICENSE.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp -R "$ROOT_DIR/LICENSES" "$APP_DIR/Contents/Resources/"
cp "$ROOT_DIR/overview.svg" "$APP_DIR/Contents/Resources/overview.svg"
for localization_dir in "$ROOT_DIR"/Resources/*.lproj; do
  if [[ -d "$localization_dir" ]]; then
    cp -R "$localization_dir" "$APP_DIR/Contents/Resources/"
  fi
done
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$LOGIN_ITEM_APP_DIR/Contents/MacOS/$LOGIN_ITEM_NAME"
codesign --force --sign - "$LOGIN_ITEM_APP_DIR" >/dev/null
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
