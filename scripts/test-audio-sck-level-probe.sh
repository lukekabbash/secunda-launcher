#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
BUILD_SCRIPT="$SCRIPT_DIR/build-audio-sck-level-probe.sh"
PROBE_SOURCE="$REPOSITORY_ROOT/tools/audio-sck-level-probe.swift"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-audio-sck-test.XXXXXX")
pass_count=0

cleanup() {
    if [[ -d "$TEST_ROOT" ]]; then
        /usr/bin/find "$TEST_ROOT" -depth -delete
    fi
}

trap cleanup EXIT

zsh -n "$BUILD_SCRIPT"
zsh -n "$0"
pass_count=$((pass_count + 1))
print -- "PASS: audio-only probe wrappers parse"

PROBE_BINARY=$(
    CLANG_MODULE_CACHE_PATH="$TEST_ROOT/clang-cache" \
        "$BUILD_SCRIPT" "$TEST_ROOT/audio-sck-level-probe"
)
[[ -x "$PROBE_BINARY" ]]
[[ "$(lipo -archs "$PROBE_BINARY")" == "arm64" ]]
[[ "$(codesign -d --verbose=4 "$PROBE_BINARY" 2>&1 | sed -n 's/^Identifier=//p')" \
    == "com.secunda.audio-sck-level-probe" ]]
pass_count=$((pass_count + 1))
print -- "PASS: fixed-identity Apple-Silicon probe builds"

CLANG_MODULE_CACHE_PATH="$TEST_ROOT/clang-cache" \
    xcrun swiftc \
    -swift-version 5 \
    -parse-as-library \
    -target arm64-apple-macos15.0 \
    -typecheck \
    "$REPOSITORY_ROOT/tools/audio-sck-level-engine.swift" \
    "$PROBE_SOURCE"
pass_count=$((pass_count + 1))
print -- "PASS: probe sources typecheck for macOS 15 on Apple Silicon"

env -i \
    HOME="$HOME" \
    LANG="${LANG:-en_US.UTF-8}" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="${TMPDIR:-/tmp}" \
    "$PROBE_BINARY" --self-test \
    | grep -Fq 'report redaction are deterministic'
pass_count=$((pass_count + 1))
print -- "PASS: aggregate statistics and redaction self-test"

set +e
help_text=$(
    env -i \
        HOME="$HOME" \
        LANG="${LANG:-en_US.UTF-8}" \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        TMPDIR="${TMPDIR:-/tmp}" \
        "$PROBE_BINARY" --help 2>&1
)
help_status=$?
set -e
(( help_status == 64 ))
print -r -- "$help_text" | grep -Fq 'Audio filtering is application-level'
print -r -- "$help_text" | grep -Fq 'Screen & System Audio Recording'
print -r -- "$help_text" | grep -Fq 'never changes output volume or mute state'
pass_count=$((pass_count + 1))
print -- "PASS: permission and isolation limits are explicit"

grep -Fq 'try stream.addStreamOutput(collector, type: .audio' "$PROBE_SOURCE"
if grep -Eq 'addStreamOutput\([^)]*type: \.screen' "$PROBE_SOURCE"; then
    print -u2 -- "FAIL: probe registers a pixel stream output"
    exit 1
fi
grep -Fq 'PCM_WRITTEN_TO_STORAGE=0' "$PROBE_SOURCE"
grep -Fq 'OUTPUT_VOLUME_OR_MUTE_CHANGED=0' "$PROBE_SOURCE"
grep -Fq 'CGPreflightScreenCaptureAccess()' "$PROBE_SOURCE"
grep -Fq 'no access request was made' "$PROBE_SOURCE"
grep -Fq 'NSApplication.shared.setActivationPolicy(.prohibited)' "$PROBE_SOURCE"
if grep -Fq 'CGRequestScreenCaptureAccess' "$PROBE_SOURCE"; then
    print -u2 -- "FAIL: probe may request Screen Recording permission"
    exit 1
fi
pass_count=$((pass_count + 1))
print -- "PASS: source registers audio only and fails closed before requesting privacy access"

print -- "PASS: $pass_count ScreenCaptureKit audio-probe contracts verified."
