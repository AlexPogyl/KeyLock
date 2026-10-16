#!/bin/bash
# Renders the README screenshots by launching KeyLock in demo mode on top of a
# synthetic colourful backdrop and cropping the panel out of a full-screen grab.
#
#   scripts/screenshots.sh [output-directory]
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/screenshots}"
APP="$ROOT/build/KeyLock.app/Contents/MacOS/KeyLock"
MARGIN=72

mkdir -p "$OUT"

capture() {
  local state="$1" name="$2" extra="${3:-}"
  pkill -f "KeyLock --demo" 2>/dev/null || true
  sleep 0.6

  # shellcheck disable=SC2086
  "$APP" --demo --state "$state" --backdrop $extra >/dev/null 2>&1 &
  sleep 3.5

  local info
  info="$(swift "$ROOT/scripts/window-id.swift" KeyLock | head -1)"
  if [ -z "$info" ]; then
    echo "!! panel window not found for state '$state'"
    return 1
  fi
  read -r _id x y w h <<< "$info"

  local full="/tmp/keylock-full-$name.png"
  screencapture -x "$full"

  local left=$(( x * 2 - MARGIN ))
  local top=$(( y * 2 ))
  local width=$(( w * 2 + MARGIN * 2 ))
  local height=$(( h * 2 + MARGIN ))

  sips -c "$height" "$width" --cropOffset "$top" "$left" "$full" --out "$OUT/$name.png" >/dev/null
  rm -f "$full"
  echo "  -> $OUT/$name.png  (${width}x${height})"
}

echo "==> Capturing screenshots into $OUT"
capture "default"  "01-unverified"
capture "verified" "02-ready"
capture "locked"   "03-locked"
capture "advanced" "04-advanced"

pkill -f "KeyLock --demo" 2>/dev/null || true
echo "==> Done"
