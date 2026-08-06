#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
APP_ROOT="$REPOSITORY_ROOT/dist/Secunda Launcher.app"
CONTENTS="$APP_ROOT/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$REPOSITORY_ROOT"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/secunda-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/secunda-swiftpm-cache"
SWIFT_ARGS=(--disable-sandbox --triple arm64-apple-macosx14.0)
swift build "${SWIFT_ARGS[@]}" -c release --product SecundaLauncher
BIN_PATH=$(swift build "${SWIFT_ARGS[@]}" -c release --show-bin-path)

mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_PATH/SecundaLauncher" "$MACOS/SecundaLauncher"

if [[ -d "$REPOSITORY_ROOT/Runtime/wine" ]]; then
    mkdir -p "$RESOURCES/runtime"
    ditto "$REPOSITORY_ROOT/Runtime/wine" "$RESOURCES/runtime"
fi

cp "$REPOSITORY_ROOT/packaging/Info.plist" "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP_ROOT"

echo "Built: $APP_ROOT"
echo "This local build is ad-hoc signed. Use a Developer ID identity before sharing."
