#!/bin/bash
# Builds Klip.app. Usage: ./build.sh [--install]
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Klip"
BUNDLE_ID="io.github.ixander.klip"
VERSION="0.1.0"
BUILD_DIR=".build/release"
APP="build/${APP_NAME}.app"

echo "==> swift build -c release"
swift build -c release

echo "==> Assembling bundle ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null
fi

# Signing. If a code-signing certificate (by default "Klip Dev") is present in
# the keychain, sign with it: the designated requirement is then stable, so
# permissions already granted to the app (Accessibility) survive rebuilds.
# Without such a certificate fall back to ad-hoc. Override via KLIP_SIGN_IDENTITY.
IDENTITY="${KLIP_SIGN_IDENTITY:-Klip Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    echo "==> Signing with certificate \"${IDENTITY}\""
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "==> Ad-hoc signing (no \"${IDENTITY}\" certificate — that is expected)"
    codesign --force --deep --sign - "$APP"
fi

if [ "${1:-}" = "--install" ]; then
    echo "==> Installing into /Applications"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP" "/Applications/${APP_NAME}.app"
    open "/Applications/${APP_NAME}.app"
    echo "Done: /Applications/${APP_NAME}.app launched."
else
    echo "Done: $(pwd)/$APP"
    echo "Run:     open \"$(pwd)/$APP\""
    echo "Or install: ./build.sh --install"
fi
