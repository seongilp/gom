#!/bin/bash
# Creates, signs, notarizes, and staples Gom-<version>.dmg from dist/Gom.app.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
IDENTITY="${IDENTITY:-Developer ID Application: Seongil Park (589U6DQJN8)}"
APPLE_ID="${APPLE_ID:-zihado@gmail.com}"
TEAM_ID="${TEAM_ID:-589U6DQJN8}"
DIST="dist"
APP="$DIST/Gom.app"
DMG="$DIST/Gom-$VERSION.dmg"
STAGING="$DIST/dmg-staging"

[ -d "$APP" ] || { echo "ERROR: $APP not found. Run scripts/build-app.sh first." >&2; exit 1; }
[ -n "${APP_PASSWORD:-}" ] || { echo "ERROR: APP_PASSWORD env var is required for notarization." >&2; exit 1; }

echo "==> Staging DMG contents"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating DMG"
hdiutil create -volname "Gom" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "==> Signing DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "==> Submitting for notarization (this can take a few minutes)"
xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Done: $DMG"
shasum -a 256 "$DMG"
