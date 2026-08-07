#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
SOURCE_PATH="$REPOSITORY_ROOT/tools/audio-pcm-tap-probe.swift"
ENGINE_SOURCE_PATH="$REPOSITORY_ROOT/tools/audio-pcm-tap-engine.swift"
SUPPORT_SOURCE_PATH="$REPOSITORY_ROOT/tools/audio-pcm-tap-support.swift"
TYPES_SOURCE_PATH="$REPOSITORY_ROOT/tools/audio-pcm-tap-types.swift"
INFO_PLIST_PATH="$REPOSITORY_ROOT/tools/audio-pcm-tap-probe-Info.plist"
OUTPUT_PATH=${1:-"$REPOSITORY_ROOT/build/tools/audio-pcm-tap-probe"}

mkdir -p "${OUTPUT_PATH:h}"
xcrun swiftc \
    -swift-version 5 \
    -O \
    -parse-as-library \
    -target arm64-apple-macos14.2 \
    "$TYPES_SOURCE_PATH" \
    "$SUPPORT_SOURCE_PATH" \
    "$ENGINE_SOURCE_PATH" \
    "$SOURCE_PATH" \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __info_plist \
    -Xlinker "$INFO_PLIST_PATH" \
    -o "$OUTPUT_PATH"

codesign \
    --force \
    --sign - \
    --identifier com.secunda.audio-pcm-tap-probe \
    "$OUTPUT_PATH"
chmod 755 "$OUTPUT_PATH"
print -r -- "$OUTPUT_PATH"
