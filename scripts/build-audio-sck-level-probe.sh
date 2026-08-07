#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
ENGINE_PATH="$REPOSITORY_ROOT/tools/audio-sck-level-engine.swift"
PROBE_PATH="$REPOSITORY_ROOT/tools/audio-sck-level-probe.swift"
INFO_PLIST_PATH="$REPOSITORY_ROOT/tools/audio-sck-level-probe-Info.plist"
OUTPUT_PATH=${1:-"$REPOSITORY_ROOT/build/tools/audio-sck-level-probe"}

mkdir -p "${OUTPUT_PATH:h}"
xcrun swiftc \
    -swift-version 5 \
    -O \
    -parse-as-library \
    -target arm64-apple-macos15.0 \
    "$ENGINE_PATH" \
    "$PROBE_PATH" \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __info_plist \
    -Xlinker "$INFO_PLIST_PATH" \
    -o "$OUTPUT_PATH"

codesign \
    --force \
    --sign - \
    --identifier com.secunda.audio-sck-level-probe \
    "$OUTPUT_PATH"
chmod 755 "$OUTPUT_PATH"
print -r -- "$OUTPUT_PATH"
