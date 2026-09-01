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
APP_PATH="$BUILD_DIR/DockDeck.app"
APP_BIN_PATH="$APP_PATH/Contents/MacOS/DockDeck"
APP_BRIDGE_PATH="$APP_PATH/Contents/Resources/bin/dockdeck-claude-bridge"
LICENSES_PATH="$APP_PATH/Contents/Resources/Licenses"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_PATH="$HOME/Library/Logs/DockDeck.log"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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

    # -T grants codesign key access without a keychain-unlock prompt on
    # every future run.
    security import "$CERT_DIR/cert.p12" -k "$LOGIN_KEYCHAIN" \
        -P "$CERT_PASSWORD" -T /usr/bin/codesign -A
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
cp "$REPO_DIR/assets/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$REPO_DIR/LICENSE" "$LICENSES_PATH/DockDeck.txt"
cp "$REPO_DIR/ThirdPartyLicenses/SwiftTerm.txt" "$LICENSES_PATH/SwiftTerm.txt"

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
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign "$SIGNING_IDENTITY" --identifier "$LABEL" "$APP_PATH"

# Keep Accessibility settings pointed at the signed login-item build when a
# separately packaged ad-hoc preview has also been opened on this Mac.
"$LSREGISTER" -u "$REPO_DIR/.build/release-dist/DockDeck.app" 2>/dev/null || true
"$LSREGISTER" -f "$APP_PATH"

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
        <string>$APP_BIN_PATH</string>
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

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo "Installed and started."
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
echo "Uninstall entirely: scripts/uninstall.sh"
