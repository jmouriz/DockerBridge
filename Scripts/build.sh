#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DockerBridge"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"
ARCH="$(uname -m)"

rm -rf "$APP_DIR"
rm -rf "$BUILD_DIR/DatabaseBridge.app" "$BUILD_DIR/Database Bridge.app"
rm -rf "$MODULE_CACHE_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$MODULE_CACHE_DIR"

xcrun swiftc \
  -O \
  -parse-as-library \
  -target "$ARCH-apple-macos13.0" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  "$ROOT_DIR"/Sources/DockerBridge/*.swift \
  -framework AppKit \
  -framework WebKit \
  -framework Security \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/PkgInfo" "$APP_DIR/Contents/PkgInfo"
cp "$ROOT_DIR/Resources/DockerBridge.icns" "$APP_DIR/Contents/Resources/DockerBridge.icns"
cp "$ROOT_DIR/Resources/connect.sh" "$APP_DIR/Contents/Resources/connect.sh"
cp "$ROOT_DIR/overview.svg" "$APP_DIR/Contents/Resources/overview.svg"
for localization_dir in "$ROOT_DIR"/Resources/*.lproj; do
  if [[ -d "$localization_dir" ]]; then
    cp -R "$localization_dir" "$APP_DIR/Contents/Resources/"
  fi
done
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/Resources/connect.sh"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
