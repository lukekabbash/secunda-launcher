#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
APP_ROOT="$REPOSITORY_ROOT/dist/Secunda Launcher.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPOSITORY_ROOT/packaging/Info.plist")
DMG_PATH="$REPOSITORY_ROOT/dist/Secunda Launcher-${VERSION}.dmg"
CHECKSUM_PATH="${DMG_PATH}.sha256"
STAGING_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-share.XXXXXX")

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

cd "$REPOSITORY_ROOT"
SECUNDA_BUNDLE_RUNTIME=0 "$SCRIPT_DIR/package-app.sh"

if [[ -e "$APP_ROOT/Contents/Resources/runtime" ]]; then
    echo "Refusing to package a local runtime in the share DMG." >&2
    exit 1
fi

if find "$APP_ROOT" \( -iname 'steam.exe' -o -iname 'skyrimse.exe' -o -path '*CrossOver.app*' \) -print -quit | grep -q .; then
    echo "Refusing to package Steam, Skyrim, or CrossOver in the share DMG." >&2
    exit 1
fi

codesign --verify --deep --strict "$APP_ROOT"
ditto "$APP_ROOT" "$STAGING_ROOT/Secunda Launcher.app"
cp "$REPOSITORY_ROOT/docs/START_HERE.txt" "$STAGING_ROOT/START HERE.txt"
ln -s /Applications "$STAGING_ROOT/Applications"

hdiutil create \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    -volname "Secunda Launcher" \
    -srcfolder "$STAGING_ROOT" \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"

if [[ -n "${SECUNDA_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$SECUNDA_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
else
    echo "Not notarized. Set SECUNDA_NOTARY_PROFILE after signing with a Developer ID identity for a frictionless recipient install."
fi

echo "Share DMG: $DMG_PATH"
echo "SHA-256: $CHECKSUM_PATH"
