#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
APP_ROOT="$REPOSITORY_ROOT/dist/Secunda Launcher.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$REPOSITORY_ROOT/packaging/Info.plist")
TEST_ONLY_MODE=${SECUNDA_TEST_ONLY_UNNOTARIZED_DMG:-0}
SIGNING_IDENTITY=${SECUNDA_SIGNING_IDENTITY:--}
NOTARY_PROFILE=${SECUNDA_NOTARY_PROFILE:-}
case "$TEST_ONLY_MODE" in
    0)
        if [[ "$SIGNING_IDENTITY" != "Developer ID Application: "* ]]; then
            echo "Recipient releases require SECUNDA_SIGNING_IDENTITY='Developer ID Application: ...'." >&2
            echo "For a clearly labeled local artifact only, set SECUNDA_TEST_ONLY_UNNOTARIZED_DMG=1." >&2
            exit 64
        fi
        if [[ -z "$NOTARY_PROFILE" ]]; then
            echo "Recipient releases require SECUNDA_NOTARY_PROFILE." >&2
            echo "For a clearly labeled local artifact only, set SECUNDA_TEST_ONLY_UNNOTARIZED_DMG=1." >&2
            exit 64
        fi
        FINAL_DMG_PATH="$REPOSITORY_ROOT/dist/Secunda Launcher-${VERSION}.dmg"
        ;;
    1)
        FINAL_DMG_PATH="$REPOSITORY_ROOT/dist/Secunda Launcher-${VERSION}-TEST-ONLY.dmg"
        echo "TEST-ONLY packaging mode: this artifact is not a recipient-ready release."
        ;;
    *)
        echo "SECUNDA_TEST_ONLY_UNNOTARIZED_DMG must be 0 or 1." >&2
        exit 64
        ;;
esac
FINAL_CHECKSUM_PATH="${FINAL_DMG_PATH}.sha256"
mkdir -p "$REPOSITORY_ROOT/dist"
STAGING_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-share.XXXXXX")
DMG_CANDIDATE_ROOT=$(mktemp -d "$REPOSITORY_ROOT/dist/.secunda-dmg-stage.XXXXXX")
DMG_PATH="$DMG_CANDIDATE_ROOT/${FINAL_DMG_PATH:t}"
CHECKSUM_PATH="$DMG_CANDIDATE_ROOT/${FINAL_CHECKSUM_PATH:t}"
PRESERVE_DMG_CANDIDATE=0
SOURCE_ARCHIVE=${SECUNDA_SOURCE_ARCHIVE:-"$REPOSITORY_ROOT/crossover-sources-26.3.0.tar.gz"}
SOURCE_ARCHIVE_NAME=crossover-sources-26.3.0.tar.gz
RUNTIME_SOURCE=${SECUNDA_RUNTIME_SOURCE:-"$REPOSITORY_ROOT/Runtime/wine-macos15"}
NETTLE_ARCHIVE="$REPOSITORY_ROOT/build/source-cache/nettle-3.10.tar.gz"
EXPECTED_NETTLE_SHA256=b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c
EXPECTED_SOURCE_SHA256=$(/usr/bin/plutil -extract sourceArchive.sha256 raw -o - \
    "$REPOSITORY_ROOT/packaging/runtime-provenance.json")
required_source_bundle_files=(
    tools/secunda-rosetta-debug-broker.c
    scripts/fetch-vulkan-stack.sh
    licenses/DXMT-v0.80-LICENSE.txt
    licenses/DXVK-v1.10.3-LICENSE.txt
    licenses/MoltenVK-v1.4.2-LICENSE.txt
    licenses/SDL2-v2.32.10-LICENSE.txt
)

cleanup() {
    rm -rf "$STAGING_ROOT"
    if (( ${PRESERVE_DMG_CANDIDATE:-0} == 1 )); then
        echo "Preserved failed DMG publication transaction for recovery: $DMG_CANDIDATE_ROOT" >&2
    else
        rm -rf "$DMG_CANDIDATE_ROOT"
    fi
}
trap cleanup EXIT

cd "$REPOSITORY_ROOT"
if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    echo "Corresponding source archive not found: $SOURCE_ARCHIVE" >&2
    echo "Set SECUNDA_SOURCE_ARCHIVE to crossover-sources-26.3.0.tar.gz." >&2
    exit 1
fi
if [[ ! -x "$RUNTIME_SOURCE/bin/wine" ]]; then
    echo "Verified macOS 15 source runtime not found: $RUNTIME_SOURCE" >&2
    echo "Set SECUNDA_RUNTIME_SOURCE to the completed source-only runtime." >&2
    exit 1
fi
if [[ ! -f "$NETTLE_ARCHIVE" ]]; then
    echo "Verified Nettle source archive is missing: $NETTLE_ARCHIVE" >&2
    echo "Run scripts/build-runtime-dependencies.sh before packaging." >&2
    exit 1
fi
for required_source_bundle_file in "${required_source_bundle_files[@]}"; do
    if [[ ! -f "$REPOSITORY_ROOT/$required_source_bundle_file" ]]; then
        echo "Required source-bundle input is missing: $required_source_bundle_file" >&2
        exit 1
    fi
done
"$SCRIPT_DIR/verify-build-provenance.sh" "$SOURCE_ARCHIVE"
SECUNDA_BUNDLE_RUNTIME=1 SECUNDA_RUNTIME_SOURCE="$RUNTIME_SOURCE" \
    "$SCRIPT_DIR/package-app.sh"

if [[ ! -x "$APP_ROOT/Contents/Resources/runtime/bin/wine" ]]; then
    echo "Refusing to package a source-only DMG without its runtime." >&2
    exit 1
fi

if find "$APP_ROOT" \( -iname 'steam.exe' -o -iname 'skyrimse.exe' -o -path '*CrossOver.app*' \) -print -quit | grep -q .; then
    echo "Refusing to package Steam, Skyrim, or CrossOver in the share DMG." >&2
    exit 1
fi

codesign --verify --deep --strict "$APP_ROOT"
ditto "$APP_ROOT" "$STAGING_ROOT/Secunda Launcher.app"
install -m 0644 "$REPOSITORY_ROOT/packaging/source-only/START_HERE.txt" \
    "$STAGING_ROOT/START HERE.txt"
ln -s /Applications "$STAGING_ROOT/Applications"

actual_source_sha256=$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{print $1}')
if [[ "$actual_source_sha256" != "$EXPECTED_SOURCE_SHA256" ]]; then
    echo "Corresponding source archive checksum mismatch." >&2
    echo "Expected: $EXPECTED_SOURCE_SHA256" >&2
    echo "Actual:   $actual_source_sha256" >&2
    exit 1
fi

SOURCE_STAGING="$STAGING_ROOT/Sources"
mkdir -p "$SOURCE_STAGING/scripts" "$SOURCE_STAGING/tools" \
    "$SOURCE_STAGING/packaging" "$SOURCE_STAGING/licenses" \
    "$SOURCE_STAGING/build/source-cache"
ditto "$SOURCE_ARCHIVE" "$SOURCE_STAGING/$SOURCE_ARCHIVE_NAME"
actual_nettle_sha256=$(shasum -a 256 "$NETTLE_ARCHIVE" | awk '{print $1}')
if [[ "$actual_nettle_sha256" != "$EXPECTED_NETTLE_SHA256" ]]; then
    echo "Nettle source archive checksum mismatch during packaging." >&2
    exit 1
fi
ditto "$NETTLE_ARCHIVE" "$SOURCE_STAGING/build/source-cache/${NETTLE_ARCHIVE:t}"
ditto "$REPOSITORY_ROOT/patches" "$SOURCE_STAGING/patches"
install -m 0644 "$REPOSITORY_ROOT/packaging/source-only/SOURCE_BUNDLE_README.txt" \
    "$SOURCE_STAGING/README.txt"
install -m 0644 "$REPOSITORY_ROOT/packaging/THIRD_PARTY_NOTICES.txt" \
    "$SOURCE_STAGING/packaging/THIRD_PARTY_NOTICES.txt"
install -m 0644 "$REPOSITORY_ROOT/packaging/runtime-provenance.json" \
    "$SOURCE_STAGING/packaging/runtime-provenance.json"
install -m 0644 "$REPOSITORY_ROOT/packaging/runtime-sbom.spdx.json" \
    "$SOURCE_STAGING/packaging/runtime-sbom.spdx.json"
install -m 0644 "$REPOSITORY_ROOT/packaging/WineRuntime.entitlements" \
    "$SOURCE_STAGING/packaging/WineRuntime.entitlements"
install -m 0644 "$REPOSITORY_ROOT/tools/secunda-rosetta-debug-broker.c" \
    "$SOURCE_STAGING/tools/secunda-rosetta-debug-broker.c"
for runtime_license in \
    DXMT-v0.80-LICENSE.txt \
    DXVK-v1.10.3-LICENSE.txt \
    MoltenVK-v1.4.2-LICENSE.txt \
    SDL2-v2.32.10-LICENSE.txt; do
    install -m 0644 "$REPOSITORY_ROOT/licenses/$runtime_license" \
        "$SOURCE_STAGING/licenses/$runtime_license"
done
for build_script in \
    build-runtime-dependencies.sh \
    build-runtime-from-archive.sh \
    build-runtime.sh \
    create-runtime-integrity.sh \
    fetch-dxmt.sh \
    fetch-vulkan-stack.sh \
    publish-runtime-directory.sh \
    relocate-runtime.sh \
    stage-runtime-notices.sh \
    verify-build-provenance.sh \
    verify-packaged-app.sh \
    verify-runtime-dependencies.sh \
    verify-runtime-integrity.sh \
    verify-runtime-payload.sh \
    verify-runtime-distribution.sh; do
    install -m 0755 "$SCRIPT_DIR/$build_script" "$SOURCE_STAGING/scripts/$build_script"
done
ditto "$APP_ROOT/Contents/Resources/runtime/share/secunda/licenses" \
    "$STAGING_ROOT/Open Source Licenses"

SOURCE_CHECKSUM_PATH="$SOURCE_STAGING/SOURCE_FILES.sha256"
(
    cd "$SOURCE_STAGING"
    find . -type f ! -path './SOURCE_FILES.sha256' -print0 | LC_ALL=C sort -z |
        xargs -0 shasum -a 256
) > "$SOURCE_CHECKSUM_PATH"

hdiutil create \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    -volname "Secunda Launcher" \
    -srcfolder "$STAGING_ROOT" \
    "$DMG_PATH"

if [[ "$TEST_ONLY_MODE" == "0" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
else
    echo "Skipping mandatory release notarization because TEST-ONLY packaging mode was explicitly selected."
fi

hdiutil verify "$DMG_PATH"
(
    cd "${DMG_PATH:h}"
    shasum -a 256 "${DMG_PATH:t}"
) > "$CHECKSUM_PATH"

VERIFY_ARGS=("$DMG_PATH" "$CHECKSUM_PATH")
if [[ "$TEST_ONLY_MODE" == "1" ]]; then
    VERIFY_ARGS+=(--test-only)
fi
"$SCRIPT_DIR/verify-share-dmg.sh" "${VERIFY_ARGS[@]}"
PRESERVE_DMG_CANDIDATE=1
if ! "$SCRIPT_DIR/publish-dmg-pair.sh" \
    "$DMG_PATH" "$CHECKSUM_PATH" "$FINAL_DMG_PATH" "$FINAL_CHECKSUM_PATH"; then
    PRESERVE_DMG_CANDIDATE=1
    echo "Verified DMG publication failed; the previous release was not intentionally discarded." >&2
    exit 1
fi
PRESERVE_DMG_CANDIDATE=0

if [[ "$TEST_ONLY_MODE" == "1" ]]; then
    echo "TEST-ONLY DMG (not recipient-ready): $FINAL_DMG_PATH"
else
    echo "Recipient-ready signed and notarized DMG: $FINAL_DMG_PATH"
fi
echo "SHA-256: $FINAL_CHECKSUM_PATH"
