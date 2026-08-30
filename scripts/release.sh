#!/bin/bash
#
# Builds, signs, notarizes and packages Top Notch for public distribution.
#
#   ./scripts/release.sh                 # unsigned local build, for testing the pipeline
#   ./scripts/release.sh --sign          # Developer ID signed + hardened runtime
#   ./scripts/release.sh --sign --notarize   # the full shipping path
#
# Credentials are read from the environment, never stored here:
#   DEVELOPER_ID   "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE name of a stored notarytool keychain profile
#
# Create the notary profile once, interactively:
#   xcrun notarytool store-credentials "topnotch" \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
set -euo pipefail

APP_NAME="Top Notch"
BUNDLE_ID="com.hivinz.topnotch"
# Marketing version. CFBundleVersion is derived below so every build is unique, which
# matters because Sparkle and macOS both compare build numbers, not marketing strings.
VERSION="1.0.0"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/apps/SideNotchMac"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

SIGN=false
NOTARIZE=false
for arg in "$@"; do
    case "$arg" in
        --sign) SIGN=true ;;
        --notarize) SIGN=true; NOTARIZE=true ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
fail() { printf '\033[31merror: %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
step "Preflight"

if $SIGN; then
    [ -n "${DEVELOPER_ID:-}" ] || fail "DEVELOPER_ID is not set. Run: security find-identity -v -p codesigning"
    security find-identity -v -p codesigning | grep -q "Developer ID Application" \
        || fail "no Developer ID Application certificate in the keychain"
fi
if $NOTARIZE; then
    [ -n "${NOTARY_PROFILE:-}" ] || fail "NOTARY_PROFILE is not set (see the header of this script)"
fi

# A dirty tree means the artefact cannot be traced back to a commit. Warn rather than
# refuse: the flag exists to build a release candidate from a work in progress.
if [ -n "$(git -C "$ROOT" status --porcelain)" ]; then
    echo "  warning: working tree is dirty; this build is not reproducible from a commit"
fi
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
# Monotonic and unique per build. Date-based so it always increases without a counter
# to keep in sync across machines.
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
echo "  version $VERSION ($BUILD_NUMBER) from $COMMIT"

# ---------------------------------------------------------------------------
step "Building universal binary (arm64 + x86_64)"

# Both architectures, because a Developer ID app is downloaded directly and there is no
# App Store thinning to produce a per-machine slice.
swift build -c release --package-path "$PKG" --arch arm64 --arch x86_64
BIN="$(swift build -c release --package-path "$PKG" --arch arm64 --arch x86_64 --show-bin-path)/SideNotchMac"
[ -f "$BIN" ] || fail "binary not produced at $BIN"

lipo -archs "$BIN" | grep -q "arm64" || fail "binary is missing arm64"
lipo -archs "$BIN" | grep -q "x86_64" || fail "binary is missing x86_64"
echo "  architectures: $(lipo -archs "$BIN")"

# ---------------------------------------------------------------------------
step "Assembling the bundle"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

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
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <!-- Background utility: menu bar and notch only, no Dock icon, no main window. -->
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Top Notch</string>
    <!-- Records the source revision in the shipped bundle, so a bug report identifies a build. -->
    <key>TopNotchSourceRevision</key><string>$COMMIT</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------------------
step "Signing"

if $SIGN; then
    # --options runtime is the hardened runtime, and notarization refuses anything without
    # it. No entitlements file: this app needs none, and under a hardened runtime the
    # least-privilege position is to request nothing at all. See docs/RELEASE.md for why
    # the App Sandbox is not used.
    codesign --force --deep --options runtime --timestamp \
        --sign "$DEVELOPER_ID" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
    echo "  signed with: $DEVELOPER_ID"
else
    # Ad-hoc. Enough for SMAppService to register a login item locally; useless for
    # distribution, and Gatekeeper will refuse it on any other machine.
    codesign --force --deep --sign - "$APP"
    echo "  ad-hoc signed (local testing only — NOT distributable)"
fi

# ---------------------------------------------------------------------------
step "Packaging DMG"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
# The Applications symlink is what makes the drag-to-install gesture obvious without a
# custom background image.
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
echo "  $DMG"

# ---------------------------------------------------------------------------
step "Notarizing"

if $NOTARIZE; then
    # The DMG is submitted rather than a zip, so the ticket can be stapled to the thing
    # the user actually downloads.
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    echo "  notarized and stapled"
else
    echo "  skipped (pass --notarize)"
fi

# ---------------------------------------------------------------------------
step "Validating"

"$ROOT/scripts/validate-release.sh" "$APP" "$DMG" "$SIGN" "$NOTARIZE"

printf '\n\033[32m✓ %s %s (%s) ready: %s\033[0m\n' "$APP_NAME" "$VERSION" "$BUILD_NUMBER" "$DMG"
