#!/bin/bash
# Stops DockDeck and removes it as a login item.
set -euo pipefail

LABEL="com.dockdeck.app"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"

echo "Removed login item ($PLIST_PATH)."
