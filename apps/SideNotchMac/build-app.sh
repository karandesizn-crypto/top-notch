#!/bin/bash
# Builds SideNotch.app.
#
# A bundle is not cosmetic here: SMAppService (launch at login) and
# UNUserNotificationCenter (threshold alerts) both require a bundle identifier and do
# nothing from a bare `swift run`. Ad-hoc signing is enough for local use; distribution
# needs a Developer ID and notarization.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/SideNotch.app"
VERSION="1.0.0"

echo "Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/SideNotchMac"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SideNotch"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SideNotch</string>
    <key>CFBundleDisplayName</key><string>SideNotch</string>
    <key>CFBundleIdentifier</key><string>app.sidenotch.SideNotch</string>
    <key>CFBundleExecutable</key><string>SideNotch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Background utility: menu bar and rail only, no Dock icon. -->
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>SideNotch</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. Without any signature the login-item registration is rejected.
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null \
    || echo "warning: ad-hoc signing failed; launch at login may not register"

echo "Built $APP"
