#!/bin/bash
#
# Checks a built bundle against the things that actually go wrong on a release.
#
# Every one of these has a specific failure it is guarding: a bundle that launches on the
# build machine and nowhere else, a plist that claims an OS it cannot run on, an ad-hoc
# signature shipped by accident, a debug surface left in a public build.
#
#   ./scripts/validate-release.sh <app> [dmg] [signed] [notarized]
#
set -uo pipefail

APP="${1:?usage: validate-release.sh <app> [dmg] [signed] [notarized]}"
DMG="${2:-}"
EXPECT_SIGNED="${3:-false}"
EXPECT_NOTARIZED="${4:-false}"

PASS=0
FAIL=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  \033[33m·\033[0m %s\n' "$1"; }

PLIST="$APP/Contents/Info.plist"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }

echo "Bundle"
[ -d "$APP" ] && ok "bundle exists" || { bad "no bundle at $APP"; exit 1; }

EXE="$(read_plist CFBundleExecutable)"
[ -x "$APP/Contents/MacOS/$EXE" ] \
    && ok "CFBundleExecutable '$EXE' exists and is executable" \
    || bad "CFBundleExecutable '$EXE' does not match the binary in MacOS/"

for key in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion; do
    value="$(read_plist "$key")"
    [ -n "$value" ] && ok "$key = $value" || bad "$key is missing"
done

# LSUIElement is what keeps a menu-bar utility out of the Dock and the app switcher.
[ "$(read_plist LSUIElement)" = "true" ] \
    && ok "LSUIElement set (no Dock icon)" \
    || bad "LSUIElement not set — the app will show a Dock icon"

echo
echo "Architecture"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/$EXE" 2>/dev/null)"
case "$ARCHS" in
    *arm64*x86_64*|*x86_64*arm64*) ok "universal ($ARCHS)" ;;
    *) bad "not universal ($ARCHS) — Intel Macs cannot run this" ;;
esac

# The plist claiming an older macOS than the binary was built for is a crash on launch
# for exactly the users least able to diagnose it.
MINOS="$(otool -l "$APP/Contents/MacOS/$EXE" 2>/dev/null | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
CLAIMED="$(read_plist LSMinimumSystemVersion)"
[ "$MINOS" = "$CLAIMED" ] \
    && ok "binary minos $MINOS matches LSMinimumSystemVersion $CLAIMED" \
    || bad "binary minos $MINOS but plist claims $CLAIMED — will crash on older macOS"

echo
echo "Signature"
if codesign --verify --deep --strict "$APP" 2>/dev/null; then
    ok "signature verifies"
else
    bad "signature does not verify"
fi

AUTHORITY="$(codesign -dvv "$APP" 2>&1 | grep '^Authority=' | head -1 | cut -d= -f2-)"
if [ "$EXPECT_SIGNED" = "true" ]; then
    case "$AUTHORITY" in
        "Developer ID Application"*) ok "signed by $AUTHORITY" ;;
        *) bad "expected a Developer ID signature, found: ${AUTHORITY:-none}" ;;
    esac
    # Notarization refuses anything without the hardened runtime, so catching it here
    # saves a round trip to Apple.
    codesign -dvv "$APP" 2>&1 | grep -q "flags=.*runtime" \
        && ok "hardened runtime enabled" \
        || bad "hardened runtime NOT enabled — notarization will reject this"
else
    note "ad-hoc signed (${AUTHORITY:-none}) — local testing only"
fi

echo
echo "Gatekeeper"
if [ "$EXPECT_NOTARIZED" = "true" ]; then
    if spctl --assess --type execute --verbose "$APP" 2>&1 | grep -q "accepted"; then
        ok "Gatekeeper accepts the app"
    else
        bad "Gatekeeper rejects the app"
    fi
    if [ -n "$DMG" ] && xcrun stapler validate "$DMG" >/dev/null 2>&1; then
        ok "notarization ticket stapled to the DMG"
    else
        bad "DMG has no stapled ticket — offline installs will be blocked"
    fi
else
    note "not notarized — Gatekeeper will refuse this on any other Mac"
fi

echo
echo "Release hygiene"
# Debug surfaces are compiled out under #if DEBUG. This checks the shipped binary rather
# than trusting that, because the guard is easy to get wrong and impossible to see.
if strings "$APP/Contents/MacOS/$EXE" 2>/dev/null | grep -q "SIDENOTCH_RENDER"; then
    bad "debug render mode present in the binary — this is a debug build"
else
    ok "debug diagnostic modes compiled out"
fi

if strings "$APP/Contents/MacOS/$EXE" 2>/dev/null | grep -q "SIDENOTCH_MOCK"; then
    bad "fixture mode present in the binary — this is a debug build"
else
    ok "fixture provider mode compiled out"
fi

# A hardcoded credential in a shipped binary is the one mistake with no recovery.
if strings "$APP/Contents/MacOS/$EXE" 2>/dev/null \
    | grep -qE "sk-ant-|sk-[A-Za-z0-9]{20,}|BEGIN (RSA|EC|OPENSSH) PRIVATE KEY"; then
    bad "something credential-shaped is embedded in the binary"
else
    ok "no credential-shaped strings in the binary"
fi

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
