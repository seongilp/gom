#!/bin/bash
# Builds Gom.app: universal binary, bundle assembly, codesign.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
IDENTITY="${IDENTITY:-Developer ID Application: Seongil Park (589U6DQJN8)}"
DIST="dist"
APP="$DIST/Gom.app"

echo "==> Building universal binary (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

BINARY=".build/apple/Products/Release/Gom"
[ -f "$BINARY" ] || { echo "ERROR: binary not found at $BINARY" >&2; exit 1; }

echo "==> Assembling Gom.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Gom"
sed "s/1\.0\.0/$VERSION/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Generating icon"
swift scripts/make-icon.swift "$DIST"
iconutil -c icns "$DIST/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$DIST/AppIcon.iconset"

echo "==> Codesigning"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Done: $APP"
