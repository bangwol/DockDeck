#!/bin/bash
# Extract metadata for the self-contained SwiftPM App Intents definitions.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:?Pass the packaged .app path}"
if ! xcrun --find appintentsmetadataprocessor >/dev/null 2>&1; then
    echo "App Intents metadata requires full Xcode; actions are unavailable with Command Line Tools alone." >&2
    if [ "${DOCKDECK_REQUIRE_APP_INTENTS:-0}" = "1" ]; then exit 1; fi
    exit 0
fi
METADATA_DIR="$(mktemp -d "$REPO_DIR/.build/appintents.XXXXXX")"
trap 'rm -rf "$METADATA_DIR"' EXIT
SDK_PATH="$(xcrun --show-sdk-path)"
SWIFT_PATH="$(xcrun --find swiftc)"
TOOLCHAIN_DIR="$(dirname "$(dirname "$(dirname "$SWIFT_PATH")")")"
TARGET_TRIPLE="$(uname -m)-apple-macosx13.0"
SOURCE_PATH="$REPO_DIR/Sources/DockDeck/DockDeckIntents.swift"
printf '%s\n' '["AppIntent","AppEntity","AppEnum"]' > "$METADATA_DIR/protocols.json"
printf '%s\n' "$SOURCE_PATH" > "$METADATA_DIR/sources.txt"
printf '%s\n' "$METADATA_DIR/intents.swiftconstvalues" > "$METADATA_DIR/constants.txt"
xcrun swiftc -frontend -typecheck -warnings-as-errors -module-name DockDeck \
    -target "$TARGET_TRIPLE" -sdk "$SDK_PATH" \
    -const-gather-protocols-file "$METADATA_DIR/protocols.json" \
    -emit-const-values-path "$METADATA_DIR/intents.swiftconstvalues" "$SOURCE_PATH"
xcrun appintentsmetadataprocessor --output "$METADATA_DIR" \
    --toolchain-dir "$TOOLCHAIN_DIR" --module-name DockDeck --sdk-root "$SDK_PATH" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ {print $3}')" \
    --platform-family macOS --deployment-target 13.0 --target-triple "$TARGET_TRIPLE" \
    --source-file-list "$METADATA_DIR/sources.txt" --swift-const-vals-list "$METADATA_DIR/constants.txt"
test -s "$METADATA_DIR/Metadata.appintents/extract.actionsdata"
mkdir -p "$APP_PATH/Contents/Resources"
rm -rf "$APP_PATH/Contents/Resources/Metadata.appintents"
cp -R "$METADATA_DIR/Metadata.appintents" "$APP_PATH/Contents/Resources/"
