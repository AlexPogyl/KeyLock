#!/bin/bash
# Builds KeyLock.app into ./build (no Xcode project required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/KeyLock.app"
SDK="$(xcrun --show-sdk-path)"
DEPLOY_TARGET="${DEPLOY_TARGET:-13.0}"

echo "==> Cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling (universal)"
SOURCES=("$ROOT"/Sources/KeyLock/*.swift)

build_arch() {
  local arch="$1"
  local out="$2"
  swiftc \
    -O -whole-module-optimization \
    -target "${arch}-apple-macos${DEPLOY_TARGET}" \
    -sdk "$SDK" \
    -framework Cocoa -framework SwiftUI -framework IOKit -framework Carbon \
    -o "$out" \
    "${SOURCES[@]}"
}

build_arch "x86_64" "$BUILD/KeyLock-x86_64"
build_arch "arm64"  "$BUILD/KeyLock-arm64"
lipo -create -output "$APP/Contents/MacOS/KeyLock" "$BUILD/KeyLock-x86_64" "$BUILD/KeyLock-arm64"
rm -f "$BUILD/KeyLock-x86_64" "$BUILD/KeyLock-arm64"

echo "==> Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --identifier "com.alexpogyl.keylock" "$APP" >/dev/null 2>&1 || \
  echo "   (codesign skipped)"

echo "==> Done: $APP"
