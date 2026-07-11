#!/bin/bash
# Builds Gom.app: arm64 binary, libmpv bundling, bundle assembly, codesign.
# (arm64-only since v1.1.0: bundled libmpv from Homebrew is arm64.)
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.1.0}"
IDENTITY="${IDENTITY:-Developer ID Application: Seongil Park (589U6DQJN8)}"
DIST="dist"
APP="$DIST/Gom.app"

echo "==> Building (arm64)"
swift build -c release

BINARY=".build/release/Gom"
[ -f "$BINARY" ] || { echo "ERROR: binary not found at $BINARY" >&2; exit 1; }

echo "==> Assembling Gom.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BINARY" "$APP/Contents/MacOS/Gom"
sed "s/1\.0\.0/$VERSION/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Bundling libmpv and dependencies"
dylibbundler -of -b \
    -x "$APP/Contents/MacOS/Gom" \
    -d "$APP/Contents/Frameworks" \
    -p @executable_path/../Frameworks > /dev/null

# dylibbundler adds one LC_RPATH per fixed dependency; dyld aborts on duplicates.
dedup_rpaths() {
    local file="$1"
    otool -l "$file" | awk '/LC_RPATH/{grab=2} grab&&/ path /{print $2; grab=0}' \
        | sort | uniq -d | while IFS= read -r rpath; do
        while [ "$(otool -l "$file" | grep -c " path $rpath ")" -gt 1 ]; do
            install_name_tool -delete_rpath "$rpath" "$file" 2>/dev/null
        done
    done
}
dedup_rpaths "$APP/Contents/MacOS/Gom"
find "$APP/Contents/Frameworks" -name "*.dylib" -print0 | while IFS= read -r -d '' dylib; do
    dedup_rpaths "$dylib"
done

echo "==> Generating icon"
swift scripts/make-icon.swift "$DIST"
iconutil -c icns "$DIST/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$DIST/AppIcon.iconset"

echo "==> Codesigning (frameworks first, then app)"
find "$APP/Contents/Frameworks" -name "*.dylib" -print0 | while IFS= read -r -d '' dylib; do
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$dylib"
done
codesign --force --options runtime --timestamp \
    --entitlements Resources/Gom.entitlements \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Done: $APP ($(du -sh "$APP" | cut -f1))"
