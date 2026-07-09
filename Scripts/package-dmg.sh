#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$("$ROOT_DIR/Scripts/build.sh")"
STAGE_DIR="$BUILD_DIR/dmg-root"
MOUNT_DIR=""
RW_DMG_PATH="$BUILD_DIR/DockerBridge-rw.dmg"
DMG_PATH="$BUILD_DIR/DockerBridge.dmg"
VOLUME_NAME="DockerBridge"
APP_BUNDLE_NAME="DockerBridge.app"
BACKGROUND_DIR="$STAGE_DIR/.background"
BACKGROUND_SOURCE="$ROOT_DIR/Resources/dmg-background.svg"
BACKGROUND_FILE_NAME="dmg-background.png"
BACKGROUND_IMAGE="$BACKGROUND_DIR/$BACKGROUND_FILE_NAME"
WINDOW_WIDTH=900
WINDOW_HEIGHT=506
BACKGROUND_WIDTH=1600
BACKGROUND_HEIGHT=900

mounted=0
detach_existing_volume() {
  local mount_path
  shopt -s nullglob
  for mount_path in "/Volumes/$VOLUME_NAME" "/Volumes/$VOLUME_NAME "*; do
    if [[ -d "$mount_path" ]]; then
      hdiutil detach "$mount_path" -quiet || true
    fi
  done
  shopt -u nullglob
}

cleanup() {
  if [[ "$mounted" -eq 1 ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet || true
  fi
  rm -rf "$STAGE_DIR" "$RW_DMG_PATH"
}
trap cleanup EXIT

detach_existing_volume
rm -rf "$STAGE_DIR"
rm -f "$RW_DMG_PATH" "$DMG_PATH"
mkdir -p "$BACKGROUND_DIR"

cp -R "$APP_DIR" "$STAGE_DIR/$APP_BUNDLE_NAME"
ln -s /Applications "$STAGE_DIR/Applications"

if command -v magick >/dev/null 2>&1; then
  magick \
    -density 144 \
    "$BACKGROUND_SOURCE" \
    -resize "${BACKGROUND_WIDTH}x${BACKGROUND_HEIGHT}" \
    -background "#08111f" \
    -gravity northwest \
    -extent "${BACKGROUND_WIDTH}x${BACKGROUND_HEIGHT}" \
    "$BACKGROUND_IMAGE"
elif [[ -x /Applications/Inkscape.app/Contents/MacOS/inkscape ]]; then
  /Applications/Inkscape.app/Contents/MacOS/inkscape \
    "$BACKGROUND_SOURCE" \
    --export-type=png \
    --export-filename="$BACKGROUND_IMAGE" \
    --export-width="$BACKGROUND_WIDTH" \
    --export-height="$BACKGROUND_HEIGHT"
else
  echo "ImageMagick or Inkscape is required to generate the DMG background." >&2
  exit 1
fi

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -fs HFS+ \
  -ov \
  -format UDRW \
  "$RW_DMG_PATH" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG_PATH" -readwrite -noverify)"
MOUNT_DIR="$(printf "%s\n" "$ATTACH_OUTPUT" | sed -n 's|^/dev/.*[[:space:]]\(/Volumes/.*\)$|\1|p' | tail -n 1)"
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
  echo "$ATTACH_OUTPUT" >&2
  echo "Could not detect the DMG mount point." >&2
  exit 1
fi
mounted=1
sleep 1

/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 1000, 606}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set backgroundFile to file "$BACKGROUND_FILE_NAME" of folder ".background"
    set background picture of theViewOptions to backgroundFile
    set position of item "$APP_BUNDLE_NAME" of container window to {300, 246}
    set position of item "Applications" of container window to {600, 246}
    try
      set position of item ".background" of container window to {1800, 900}
    end try
    try
      set position of item ".fseventsd" of container window to {1900, 900}
    end try
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

/usr/bin/chflags hidden "$MOUNT_DIR/.background" || true
/usr/bin/SetFile -a V "$MOUNT_DIR/.background" || true
rm -rf "$MOUNT_DIR/.fseventsd" || true
if [[ -d "$MOUNT_DIR/.fseventsd" ]]; then
  /usr/bin/chflags hidden "$MOUNT_DIR/.fseventsd" || true
  /usr/bin/SetFile -a V "$MOUNT_DIR/.fseventsd" || true
fi

sync
hdiutil detach "$MOUNT_DIR" -quiet
mounted=0

hdiutil convert "$RW_DMG_PATH" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" \
  -ov >/dev/null

echo "$DMG_PATH"
