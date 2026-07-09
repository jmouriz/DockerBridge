#!/usr/bin/env bash

set -euo pipefail

PLIST_ID="ar.tecnologica.dockerbridge"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_ID.plist"

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"

echo "Removed $PLIST_PATH"
