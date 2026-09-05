#!/bin/bash
# Builds a universal release-candidate app and versioned zip.
# The default ad-hoc signature is suitable only for local QA. Set
# DOCKDECK_SIGNING_IDENTITY to create a Developer ID-signed candidate;
# public distribution still requires notarization.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.dockdeck.app"
ARM64_SCRATCH="$REPO_DIR/.build-arm64"
X86_64_SCRATCH="$REPO_DIR/.build-x86_64"
APP_PATH="$REPO_DIR/.build/release-dist/DockDeck.app"
APP_BIN_PATH="$APP_PATH/Contents/MacOS/DockDeck"
APP_BRIDGE_PATH="$APP_PATH/Contents/Resources/bin/dockdeck-claude-bridge"
APP_RESOURCE_BUNDLE_PATH="$APP_PATH/Contents/Resources/DockDeck_DockDeck.bundle"
LICENSES_PATH="$APP_PATH/Contents/Resources/Licenses"
VERSION="$(tr -d '[:space:]' < "$REPO_DIR/VERSION")"
SIGNING_IDENTITY="${DOCKDECK_SIGNING_IDENTITY:--}"

if [ "$SIGNING_IDENTITY" = "-" ]; then
    ZIP_NAME="DockDeck-$VERSION-macos-universal-unsigned.zip"
else
    ZIP_NAME="DockDeck-$VERSION-macos-universal.zip"
fi
ZIP_PATH="$REPO_DIR/$ZIP_NAME"
CHECKSUM_PATH="$ZIP_PATH.sha256"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must contain three numeric components (for example, 0.1.0)." >&2
    exit 1
fi

# Two single-arch builds + lipo, not `swift build --arch arm64 --arch
# x86_64` in one invocation: that form hands the universal-binary step to
# xcbuild, which needs a full Xcode install and isn't available with just
# Command Line Tools. Each --arch build also needs its own --scratch-path:
# sharing one .build/ across arches corrupts SwiftPM's build database
# (confirmed by hand -- a plain second `swift build --arch x86_64` after
# an `--arch arm64` build in the same .build/ fails with "command ...
# not registered", even though the first build's binary is still fine on
# disk). Isolated scratch dirs sidestep that entirely.
echo "Building release binary (arm64)..."
(cd "$REPO_DIR" && swift build -c release --arch arm64 --scratch-path "$ARM64_SCRATCH")

echo "Building release binary (x86_64)..."
(cd "$REPO_DIR" && swift build -c release --arch x86_64 --scratch-path "$X86_64_SCRATCH")

echo "Packaging $APP_PATH..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources/bin" "$LICENSES_PATH"
lipo -create -output "$APP_BIN_PATH" \
    "$ARM64_SCRATCH/arm64-apple-macosx/release/DockDeck" \
    "$X86_64_SCRATCH/x86_64-apple-macosx/release/DockDeck"
lipo -create -output "$APP_BRIDGE_PATH" \
    "$ARM64_SCRATCH/arm64-apple-macosx/release/dockdeck-claude-bridge" \
    "$X86_64_SCRATCH/x86_64-apple-macosx/release/dockdeck-claude-bridge"
cp -R "$ARM64_SCRATCH/arm64-apple-macosx/release/DockDeck_DockDeck.bundle" \
    "$APP_RESOURCE_BUNDLE_PATH"
cp "$REPO_DIR/assets/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$REPO_DIR/LICENSE" "$LICENSES_PATH/DockDeck.txt"
cp "$REPO_DIR/ThirdPartyLicenses/SwiftTerm.txt" "$LICENSES_PATH/SwiftTerm.txt"
cp "$REPO_DIR/ThirdPartyLicenses/Open-Meteo.txt" "$LICENSES_PATH/Open-Meteo.txt"
cp "$REPO_DIR/ThirdPartyLicenses/ProviderMarks.txt" "$LICENSES_PATH/ProviderMarks.txt"

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$LABEL</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>ko</string></array>
    <key>CFBundleAllowMixedLocalizations</key>
    <true/>
    <key>CFBundleName</key>
    <string>DockDeck</string>
    <key>CFBundleExecutable</key>
    <string>DockDeck</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>NSLocalNetworkUsageDescription</key>
    <string>DockDeck checks local service URLs that you add to Service Monitor.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>DockDeck reads upcoming event titles and times for Schedule. It never changes calendars.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>DockDeck reads upcoming event titles and times for Schedule. It never changes calendars.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>DockDeck reads incomplete reminder titles and due dates for Schedule. It never changes reminders.</string>
    <key>NSRemindersUsageDescription</key>
    <string>DockDeck reads incomplete reminder titles and due dates for Schedule. It never changes reminders.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>DockDeck reads playback details and controls the macOS Music app after you connect the Music module.</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null
DOCKDECK_REQUIRE_APP_INTENTS=1 "$REPO_DIR/scripts/build-app-intents.sh" "$APP_PATH"

if [ "$SIGNING_IDENTITY" = "-" ]; then
    echo "Ad-hoc signing $APP_PATH..."
    codesign --force --options runtime --sign - "$APP_BRIDGE_PATH"
    codesign --force --options runtime --sign - \
        --entitlements "$REPO_DIR/DockDeck.entitlements" --identifier "$LABEL" "$APP_PATH"
else
    echo "Signing $APP_PATH with the configured identity..."
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
        "$APP_BRIDGE_PATH"
    codesign --force --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" --entitlements "$REPO_DIR/DockDeck.entitlements" \
        --identifier "$LABEL" "$APP_PATH"
fi

codesign --verify --deep --strict "$APP_PATH"
lipo "$APP_BIN_PATH" -verify_arch arm64 x86_64
lipo "$APP_BRIDGE_PATH" -verify_arch arm64 x86_64

echo "Zipping..."
rm -f \
    "$REPO_DIR/DockDeck.zip" \
    "$REPO_DIR/DockDeck-$VERSION-macos-universal.zip" \
    "$REPO_DIR/DockDeck-$VERSION-macos-universal.zip.sha256" \
    "$REPO_DIR/DockDeck-$VERSION-macos-universal-unsigned.zip" \
    "$REPO_DIR/DockDeck-$VERSION-macos-universal-unsigned.zip.sha256"
ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$APP_PATH" "$ZIP_PATH"

VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/DockDeck.app"
(cd "$REPO_DIR" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")

echo
echo "Done: $ZIP_PATH"
echo "SHA-256: $CHECKSUM_PATH"
