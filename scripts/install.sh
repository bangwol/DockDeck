#!/bin/bash
# Installs DockDeck as a per-user LaunchAgent: starts it now, and arms it
# to start at every future login. Safe to re-run (e.g. after a rebuild) —
# it just rebuilds, repackages, and reloads it.
#
# Packages the binary into a minimal .app bundle and code-signs it rather
# than running the raw executable directly. This matters specifically for
# Accessibility permission (needed to track the Dock's geometry): a process
# launched by launchd needs its own stable TCC identity.
#
# The sole Apple Development identity is preferred because its Apple-anchored
# designated requirement stays stable across rebuilds. Set
# DOCKDECK_SIGNING_IDENTITY to select another identity. If neither is
# available, the installer creates a local self-signed fallback; current
# macOS releases may require Accessibility approval again after a rebuild
# when that fallback is used.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="com.dockdeck.app"
LOCAL_CERT_NAME="DockDeck Local Signing"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
BUILD_DIR="$REPO_DIR/.build/release"
BIN_PATH="$BUILD_DIR/DockDeck"
BRIDGE_BIN_PATH="$BUILD_DIR/dockdeck-claude-bridge"
RESOURCE_BUNDLE_PATH="$BUILD_DIR/DockDeck_DockDeck.bundle"
APP_PATH="$BUILD_DIR/DockDeck.app"
APP_BIN_PATH="$APP_PATH/Contents/MacOS/DockDeck"
APP_BRIDGE_PATH="$APP_PATH/Contents/Resources/bin/dockdeck-claude-bridge"
APP_RESOURCE_BUNDLE_PATH="$APP_PATH/Contents/Resources/DockDeck_DockDeck.bundle"
LICENSES_PATH="$APP_PATH/Contents/Resources/Licenses"
INSTALLED_APP_PATH="$HOME/Applications/DockDeck.app"
INSTALLED_APP_BIN_PATH="$INSTALLED_APP_PATH/Contents/MacOS/DockDeck"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_PATH="$HOME/Library/Logs/DockDeck.log"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
VERSION="$(tr -d '[:space:]' < "$REPO_DIR/VERSION")"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must contain three numeric components (for example, 0.1.0)." >&2
    exit 1
fi

SIGNING_IDENTITY="${DOCKDECK_SIGNING_IDENTITY:-}"
SIGNING_SOURCE="configured"

if [ -z "$SIGNING_IDENTITY" ]; then
    AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning "$LOGIN_KEYCHAIN")"
    APPLE_DEVELOPMENT_COUNT="$({ printf '%s\n' "$AVAILABLE_IDENTITIES" || true; } \
        | awk '/"Apple Development:/{count++} END{print count+0}')"
    APPLE_DEVELOPMENT_IDENTITY="$({ printf '%s\n' "$AVAILABLE_IDENTITIES" || true; } \
        | awk '/"Apple Development:/{identity=$2; count++} END{if(count==1) print identity}')"

    if [ "$APPLE_DEVELOPMENT_COUNT" -eq 1 ]; then
        SIGNING_IDENTITY="$APPLE_DEVELOPMENT_IDENTITY"
        SIGNING_SOURCE="apple-development"
    else
        SIGNING_IDENTITY="$LOCAL_CERT_NAME"
        SIGNING_SOURCE="local"
        if [ "$APPLE_DEVELOPMENT_COUNT" -gt 1 ]; then
            echo "Multiple Apple Development identities found."
            echo "Set DOCKDECK_SIGNING_IDENTITY to select one explicitly."
        fi
    fi
fi

if [ "$SIGNING_SOURCE" = "local" ] \
    && ! security find-certificate -c "$LOCAL_CERT_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
    echo "Creating local code-signing certificate ($LOCAL_CERT_NAME)..."
    echo "macOS will likely ask for your login password once, to confirm"
    echo "trusting this new certificate for code signing."
    CERT_DIR="$(mktemp -d)"
    trap 'rm -rf "$CERT_DIR"' EXIT
    CERT_PASSWORD="$(openssl rand -hex 32)"

    openssl req -x509 -newkey rsa:2048 -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" \
        -days 3650 -nodes -subj "/CN=$LOCAL_CERT_NAME" \
        -addext "keyUsage=digitalSignature" \
        -addext "extendedKeyUsage=codeSigning" \
        -addext "basicConstraints=critical,CA:false"

    # -legacy: OpenSSL 3.x defaults to AES/SHA-256 for PKCS12, which
    # macOS's Security framework can't parse ("MAC verification failed")
    # -- it expects the older RC2/3DES-based format this flag restores.
    openssl pkcs12 -export -legacy -out "$CERT_DIR/cert.p12" \
        -inkey "$CERT_DIR/key.pem" -in "$CERT_DIR/cert.pem" \
        -passout "pass:$CERT_PASSWORD"

    # Restrict private-key access to codesign. Do not use security import's
    # -A option, which grants every local application direct key access.
    security import "$CERT_DIR/cert.p12" -k "$LOGIN_KEYCHAIN" \
        -P "$CERT_PASSWORD" -T /usr/bin/codesign
    unset CERT_PASSWORD

    # No -d: this trusts the cert for the *user's* login keychain only,
    # not system-wide, so it doesn't need sudo.
    security add-trusted-cert -r trustRoot -p codeSign \
        -k "$LOGIN_KEYCHAIN" "$CERT_DIR/cert.pem"

    echo "Certificate created and trusted for code signing."
fi

if [ "$SIGNING_SOURCE" = "apple-development" ]; then
    echo "Using the available Apple Development signing identity."
elif [ "$SIGNING_SOURCE" = "configured" ]; then
    echo "Using DOCKDECK_SIGNING_IDENTITY."
else
    echo "Using the local self-signed fallback."
fi

echo "Building release binary..."
(cd "$REPO_DIR" && swift build -c release)

echo "Packaging $APP_PATH..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources/bin" "$LICENSES_PATH"
cp "$BIN_PATH" "$APP_BIN_PATH"
cp "$BRIDGE_BIN_PATH" "$APP_BRIDGE_PATH"
cp -R "$RESOURCE_BUNDLE_PATH" "$APP_RESOURCE_BUNDLE_PATH"
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
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_BRIDGE_PATH"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
    --identifier "$LABEL" "$APP_PATH"

launchctl unload "$PLIST_PATH" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$INSTALLED_APP_PATH"
ditto "$APP_PATH" "$INSTALLED_APP_PATH"
codesign --verify --deep --strict "$INSTALLED_APP_PATH"

# Keep Accessibility settings pointed at the stable signed installation when
# separately packaged or intermediate builds also exist on this Mac.
"$LSREGISTER" -u "$REPO_DIR/.build/release-dist/DockDeck.app" 2>/dev/null || true
"$LSREGISTER" -u "$APP_PATH" 2>/dev/null || true
"$LSREGISTER" -f "$INSTALLED_APP_PATH"

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALLED_APP_BIN_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_PATH</string>
    <key>StandardErrorPath</key>
    <string>$LOG_PATH</string>
</dict>
</plist>
EOF

launchctl load "$PLIST_PATH"

echo "Installed $INSTALLED_APP_PATH and started."
echo
echo "If the panel isn't tracking the Dock, check System Settings ->"
echo "Privacy & Security -> Accessibility for a \"DockDeck\" entry and"
echo "make sure it's enabled."
echo
echo "Turn off (stops it now, and skips it at future logins):"
echo "  launchctl unload $PLIST_PATH"
echo
echo "Turn back on:"
echo "  launchctl load $PLIST_PATH"
echo
echo "Remove the login item: scripts/uninstall.sh"
