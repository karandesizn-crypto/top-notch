#!/bin/bash
#
# Renders the four surface states offscreen and compares them against recorded hashes.
#
#   ./scripts/check-design-lock.sh          # verify
#   ./scripts/check-design-lock.sh --record # re-record after an intended change
#
# This is the mechanism that has kept the notch UI honest across every refactor: the
# renders are byte-compared, so a change nobody meant to make cannot pass unnoticed.
# Baselines live in scripts/design-lock.sha rather than in someone's shell history.
#
# Note the renders are canvas-sized from the layout, so a deliberate change to window
# geometry moves every hash even where the surface itself is untouched. When that happens,
# look at the PNGs before re-recording.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/apps/SideNotchMac"
BASELINE="$ROOT/scripts/design-lock.sha"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

RECORD=false
[ "${1:-}" = "--record" ] && RECORD=true

# Debug build: the offscreen render mode is compiled out of release on purpose.
swift build --package-path "$PKG" >/dev/null
BIN="$(swift build --package-path "$PKG" --show-bin-path)/SideNotchMac"

render() {
    local name="$1"; shift
    env SIDENOTCH_MOCK=1 SIDENOTCH_RENDER="$OUT/$name.png" "$@" "$BIN" >/dev/null 2>&1 || true
}
render rest   env
render hover  env SIDENOTCH_RENDER_EXPANDED=1 SIDENOTCH_RENDER_FOCUS=claude
render pinned env SIDENOTCH_RENDER_EXPANDED=1 SIDENOTCH_RENDER_PINNED=1
render mini   env SIDENOTCH_RENDER_MINI=1

if $RECORD; then
    : > "$BASELINE"
    for state in rest hover pinned mini; do
        echo "$state $(md5 -q "$OUT/$state.png")" >> "$BASELINE"
    done
    echo "recorded:"; cat "$BASELINE"
    exit 0
fi

drift=0
while read -r state want; do
    got="$(md5 -q "$OUT/$state.png" 2>/dev/null || echo missing)"
    if [ "$want" = "$got" ]; then
        printf '  \033[32m✓\033[0m %-7s identical\n' "$state"
    else
        printf '  \033[31m✗\033[0m %-7s DRIFT  expected %s got %s\n' "$state" "$want" "$got"
        drift=1
    fi
done < "$BASELINE"

[ $drift -eq 0 ] && echo "design lock intact" || { echo "design lock BROKEN"; exit 1; }
