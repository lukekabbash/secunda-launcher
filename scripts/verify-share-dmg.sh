#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
DMG_PATH=${1:-}
CHECKSUM_PATH=${2:-"${DMG_PATH}.sha256"}
VERIFICATION_MODE=${3:---release}
MOUNT_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-dmg-mount.XXXXXX")
INSTALL_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-dmg-install.XXXXXX")
SMOKE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/secunda-dmg-home.XXXXXX")
EXPECTED_SOURCE_FILES=$(mktemp "${TMPDIR:-/tmp}/secunda-source-files.XXXXXX")
attached=0

cleanup() {
    if (( attached == 1 )); then
        hdiutil detach "$MOUNT_ROOT" -quiet || true
    fi
    rm -rf "$MOUNT_ROOT" "$INSTALL_ROOT" "$SMOKE_HOME"
    rm -f "$EXPECTED_SOURCE_FILES"
}
trap cleanup EXIT

if [[ ! -f "$DMG_PATH" || ! -f "$CHECKSUM_PATH" ]]; then
    echo "Usage: $0 path-to.dmg [path-to.dmg.sha256] [--release|--test-only]" >&2
    exit 64
fi
case "$VERIFICATION_MODE" in
    --release|--test-only) ;;
    *)
        echo "Unknown DMG verification mode: $VERIFICATION_MODE" >&2
        exit 64
        ;;
esac

(
    cd "${DMG_PATH:h}"
    shasum -a 256 -c "${CHECKSUM_PATH:t}" >/dev/null
)

if [[ "$VERIFICATION_MODE" == "--release" ]]; then
    xcrun stapler validate "$DMG_PATH"
fi

hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_ROOT" "$DMG_PATH" -quiet
attached=1

APP_ROOT="$MOUNT_ROOT/Secunda Launcher.app"
SOURCE_ROOT="$MOUNT_ROOT/Sources"
required_paths=(
    "$APP_ROOT"
    "$MOUNT_ROOT/Applications"
    "$MOUNT_ROOT/START HERE.txt"
    "$MOUNT_ROOT/Open Source Licenses"
    "$SOURCE_ROOT/README.txt"
    "$SOURCE_ROOT/crossover-sources-26.3.0.tar.gz"
    "$SOURCE_ROOT/build/source-cache/nettle-3.10.tar.gz"
    "$SOURCE_ROOT/patches"
    "$SOURCE_ROOT/tools/secunda-rosetta-debug-broker.c"
    "$SOURCE_ROOT/scripts/build-runtime-from-archive.sh"
    "$SOURCE_ROOT/scripts/build-runtime.sh"
    "$SOURCE_ROOT/scripts/fetch-vulkan-stack.sh"
    "$SOURCE_ROOT/scripts/publish-runtime-directory.sh"
    "$SOURCE_ROOT/scripts/verify-runtime-payload.sh"
    "$SOURCE_ROOT/scripts/verify-runtime-integrity.sh"
    "$SOURCE_ROOT/packaging/WineRuntime.entitlements"
    "$SOURCE_ROOT/packaging/runtime-provenance.json"
    "$SOURCE_ROOT/packaging/runtime-sbom.spdx.json"
    "$SOURCE_ROOT/licenses/DXMT-v0.80-LICENSE.txt"
    "$SOURCE_ROOT/licenses/DXVK-v1.10.3-LICENSE.txt"
    "$SOURCE_ROOT/licenses/MoltenVK-v1.4.2-LICENSE.txt"
    "$SOURCE_ROOT/licenses/SDL2-v2.32.10-LICENSE.txt"
    "$SOURCE_ROOT/SOURCE_FILES.sha256"
)
for required_path in "${required_paths[@]}"; do
    if [[ ! -e "$required_path" ]]; then
        echo "Mounted DMG is missing: $required_path" >&2
        exit 1
    fi
done

"$SCRIPT_DIR/verify-packaged-app.sh" "$APP_ROOT"
MOUNTED_LAUNCHER="$APP_ROOT/Contents/MacOS/SecundaLauncher"
echo "Running mounted launcher self-test."
env -i \
    HOME="$SMOKE_HOME" \
    LANG=en_US.UTF-8 \
    LC_CTYPE=UTF-8 \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="${TMPDIR:-/tmp}" \
    "$MOUNTED_LAUNCHER" --self-test
if find "$SOURCE_ROOT" -type l -print -quit | grep -q .; then
    echo "Corresponding source bundle contains an unexpected symlink." >&2
    exit 1
fi
(
    cd "$SOURCE_ROOT"
    find . -type f ! -path './SOURCE_FILES.sha256' -print0 | LC_ALL=C sort -z |
        xargs -0 shasum -a 256
) > "$EXPECTED_SOURCE_FILES"
if ! cmp -s "$SOURCE_ROOT/SOURCE_FILES.sha256" "$EXPECTED_SOURCE_FILES"; then
    echo "Corresponding source inventory is incomplete, duplicated, stale, or corrupted." >&2
    exit 1
fi

INSTALLED_APP="$INSTALL_ROOT/Secunda Launcher.app"
ditto "$APP_ROOT" "$INSTALLED_APP"
INSTALLED_WINE="$INSTALLED_APP/Contents/Resources/runtime/bin/wine"
wine_version=$(env -i \
    HOME="$SMOKE_HOME" \
    LANG=en_US.UTF-8 \
    LC_CTYPE=UTF-8 \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="${TMPDIR:-/tmp}" \
    "$INSTALLED_WINE" --version)
if [[ "$wine_version" != wine-* ]]; then
    echo "Copied app runtime did not return a Wine version: $wine_version" >&2
    exit 1
fi

if [[ "$VERIFICATION_MODE" == "--release" ]]; then
    spctl --assess --type execute --verbose=4 "$INSTALLED_APP"
    echo "PASS: recipient release is stapled, Gatekeeper-accepted, source-complete, relocatable, and runs $wine_version."
else
    echo "PASS: TEST-ONLY DMG is source-complete, relocatable, and runs $wine_version; release trust was intentionally not claimed."
fi
