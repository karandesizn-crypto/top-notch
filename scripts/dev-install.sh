#!/bin/bash
#
# Builds Top Notch and installs it for personal daily use on this Mac.
#
#   ./scripts/dev-install.sh            # build, install, relaunch
#   ./scripts/dev-install.sh --debug    # debug build (keeps the diagnostic modes)
#   ./scripts/dev-install.sh --no-launch
#
# No Developer ID, no notarization, no DMG. This produces an ad-hoc signed bundle that
# runs on this machine and nowhere else, which is exactly what a personal alpha needs.
# `scripts/release.sh` remains for the day that changes.
#
set -euo pipefail

APP_NAME="Top Notch"
BUNDLE_ID="com.hivinz.topnotch"
VERSION="1.0.0"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/apps/SideNotchMac"
# ~/Applications rather than the repo: the app has to keep running while the working tree
# is rebuilt, moved or cleaned, and a bundle living inside the checkout does not survive
# that. No sudo either, unlike /Applications.
DEST_DIR="$HOME/Applications"
APP="$DEST_DIR/$APP_NAME.app"

CONFIG="release"
LAUNCH=true
for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG="debug" ;;
        --no-launch) LAUNCH=false ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
step "Building ($CONFIG, arm64)"

# This Mac only. A universal binary doubles build time for a slice that will never run
# here; `release.sh` builds both when that actually matters.
swift build -c "$CONFIG" --package-path "$PKG" --arch arm64
BIN="$(swift build -c "$CONFIG" --package-path "$PKG" --arch arm64 --show-bin-path)/SideNotchMac"
[ -f "$BIN" ] || { echo "error: no binary at $BIN" >&2; exit 1; }

# ---------------------------------------------------------------------------
step "Stopping the running copy"

# Matched on bundle identifier rather than name, so this cannot match an unrelated
# process that happens to have "Top Notch" in its path.
if pgrep -f "$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        pgrep -f "$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.25
    done
    # Terminating cleanly matters: the app stops the Codex app-server child process in
    # applicationWillTerminate, and a killed parent leaves that child running.
    pkill -f "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    echo "  stopped"
else
    echo "  not running"
fi

# ---------------------------------------------------------------------------
step "Installing to $APP"

mkdir -p "$DEST_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# CFBundleVersion is fixed rather than a build timestamp. A changing build number would
# make every rebuild a "different version" to macOS for no local benefit; the release
# script generates a real one when a build is actually being distributed.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Top Notch</string>
</dict>
</plist>
PLIST

# Ad-hoc. Enough for SMAppService to register a login item; not distributable.
codesign --force --deep --sign - "$APP" 2>/dev/null

# ---------------------------------------------------------------------------
step "Checking"

CDHASH="$(codesign -dvvv "$APP" 2>&1 | awk -F= '/^CDHash/{print $2; exit}')"
echo "  version   $VERSION ($CONFIG, arm64)"
echo "  cdhash    ${CDHASH:0:16}…"

# The keychain ACL that lets the Claude adapter read Claude Code's login is bound to the
# code signature. An ad-hoc signature has no stable identity, so its designated
# requirement is the cdhash — which changes whenever the binary does. That is why macOS
# asks again after a rebuild that changed any code: it genuinely is a different program as
# far as the keychain is concerned. Nothing is wrong, and nothing is lost by allowing it.
if [ -f "$HOME/.topnotch-dev-cdhash" ] && [ "$(cat "$HOME/.topnotch-dev-cdhash")" = "$CDHASH" ]; then
    echo "  keychain  unchanged signature — no new prompt expected"
else
    echo "  keychain  signature changed — macOS will ask once for 'Claude Code-credentials'"
fi
printf '%s' "$CDHASH" > "$HOME/.topnotch-dev-cdhash"

# ---------------------------------------------------------------------------
if $LAUNCH; then
    step "Launching"
    open "$APP"
    sleep 2
    if pgrep -f "$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
        echo "  running (menu bar icon + notch surface; no Dock icon by design)"
    else
        echo "  warning: did not stay running — check: log show --predicate 'subsystem == \"$BUNDLE_ID\"' --last 2m"
    fi
fi

printf '\n\033[32m✓ %s installed at %s\033[0m\n' "$APP_NAME" "$APP"
