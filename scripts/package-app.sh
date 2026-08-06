#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
APP_ROOT="$REPOSITORY_ROOT/dist/Secunda Launcher.app"
CONTENTS="$APP_ROOT/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
RUNTIME_MODE="${SECUNDA_BUNDLE_RUNTIME:-0}"
SIGNING_IDENTITY="${SECUNDA_SIGNING_IDENTITY:--}"

cd "$REPOSITORY_ROOT"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/secunda-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/secunda-swiftpm-cache"
SWIFT_ARGS=(--disable-sandbox --triple arm64-apple-macosx14.0)
swift build "${SWIFT_ARGS[@]}" -c release --product SecundaLauncher
BIN_PATH=$(swift build "${SWIFT_ARGS[@]}" -c release --show-bin-path)

mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_PATH/SecundaLauncher" "$MACOS/SecundaLauncher"

case "$RUNTIME_MODE" in
    0|1) ;;
    *)
        echo "SECUNDA_BUNDLE_RUNTIME must be 0 or 1." >&2
        exit 64
        ;;
esac

# A share build must never inherit a stale local runtime from an older package.
rm -rf "$RESOURCES/runtime"
if [[ "$RUNTIME_MODE" == "1" && -d "$REPOSITORY_ROOT/Runtime/wine" ]]; then
    mkdir -p "$RESOURCES/runtime"
    ditto "$REPOSITORY_ROOT/Runtime/wine" "$RESOURCES/runtime"
fi

cp "$REPOSITORY_ROOT/packaging/Info.plist" "$CONTENTS/Info.plist"
SIGNING_ARGS=(--force --deep --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    SIGNING_ARGS+=(--options runtime --timestamp)
fi
codesign "${SIGNING_ARGS[@]}" "$APP_ROOT"

echo "Built: $APP_ROOT"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "This local build is ad-hoc signed. Use a Developer ID identity and notarization before broad sharing."
else
    echo "Signed with: $SIGNING_IDENTITY"
fi
