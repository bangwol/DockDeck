#!/bin/bash
# Stops DockDeck and removes its login registration; keeps the app and settings.
set -euo pipefail
LABEL="com.dockdeck.app"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_PATH="$HOME/Applications/DockDeck.app"
CONTROL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :DockDeckLoginItemControlVersion' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
if [ "$CONTROL_VERSION" = "1" ]; then
    "$APP_PATH/Contents/MacOS/DockDeck" --disable-login-item
    "$APP_PATH/Contents/MacOS/DockDeck" --stop-installed-app
elif [ ! -f "$PLIST_PATH" ]; then
    echo "No controllable installed app found. Check System Settings -> General -> Login Items for a remaining DockDeck entry." >&2
    exit 1
fi
launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"
echo "Stopped DockDeck and removed its login registration. App and settings were kept."
