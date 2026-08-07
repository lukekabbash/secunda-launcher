#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
HUD_PROBE="$REPOSITORY_ROOT/tools/metal-hud-probe.swift"
CADENCE_PROBE="$REPOSITORY_ROOT/tools/window-frame-cadence.swift"
CACHE_SNAPSHOT="$SCRIPT_DIR/snapshot-dxmt-cache.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-gate-performance-test.XXXXXX")
pass_count=0

cleanup() {
    if [[ -d "$TEST_ROOT" ]]; then
        /usr/bin/find "$TEST_ROOT" -depth -delete
    fi
}

trap cleanup EXIT

run_swift() {
    env -i \
        HOME="$HOME" \
        LANG="${LANG:-en_US.UTF-8}" \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        TMPDIR="${TMPDIR:-/tmp}" \
        CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/secunda-gate-performance-clang-cache" \
        /usr/bin/swift "$@"
}

run_swift "$HUD_PROBE" --self-test
pass_count=$((pass_count + 1))

run_swift "$CADENCE_PROBE" --self-test
pass_count=$((pass_count + 1))

{
    print -r -- '{"processID":4242,"subsystem":"com.apple.metal.hud","eventMessage":"metal-HUD: 10,100,200,16.0,5.0,18.0,7.0"}'
    print -r -- '{"processID":4242,"subsystem":"com.apple.metal.hud","eventMessage":"CompileShader: name: do-not-record-this compilation-time: 12345 cached: 0"}'
    print -r -- '{"processID":9999,"subsystem":"com.apple.metal.hud","eventMessage":"metal-HUD: 1,1,1,999,999"}'
} > "$TEST_ROOT/hud.ndjson"

run_swift "$HUD_PROBE" \
    --input "$TEST_ROOT/hud.ndjson" \
    --pid 4242 \
    --window-id 77 \
    --target-fps 60 \
    --report "$TEST_ROOT/report.txt"

grep -Fq 'PROCESS_ID=4242' "$TEST_ROOT/report.txt"
grep -Fq 'WINDOW_ID=77' "$TEST_ROOT/report.txt"
grep -Fq 'PRESENT_INTERVAL_MS_COUNT=2' "$TEST_ROOT/report.txt"
grep -Fq 'PRESENT_INTERVAL_MS_P50=17.000' "$TEST_ROOT/report.txt"
grep -Fq 'SHADER_CACHE_MISSES=1' "$TEST_ROOT/report.txt"
grep -Fq 'PRIVACY=raw-log-events-and-shader-names-omitted' "$TEST_ROOT/report.txt"
if grep -Fq 'do-not-record-this' "$TEST_ROOT/report.txt"; then
    print -u2 -- "FAIL: a shader name leaked into the report"
    exit 1
fi
if grep -Fq '999.000' "$TEST_ROOT/report.txt"; then
    print -u2 -- "FAIL: an unrelated process event entered the report"
    exit 1
fi
pass_count=$((pass_count + 1))
print -- "PASS: exact-PID HUD summary is privacy-safe"

mkdir -p "$TEST_ROOT/cache/com.apple.metal/device"
print -nr -- 'database' > "$TEST_ROOT/cache/shaders_320.db"
print -nr -- 'journal' > "$TEST_ROOT/cache/shaders_320.db-wal"
print -nr -- 'pipeline' > "$TEST_ROOT/cache/com.apple.metal/device/functions.data"
"$CACHE_SNAPSHOT" \
    --label TEST \
    --shader-root "$TEST_ROOT/cache" \
    --shader-root "$TEST_ROOT/cache" \
    --metal-root "$TEST_ROOT/cache/com.apple.metal" \
    > "$TEST_ROOT/cache-report.txt"
grep -Fq 'TEST_DXMT_SHADER_CACHE_FILE_COUNT=2' "$TEST_ROOT/cache-report.txt"
grep -Fq 'TEST_METAL_PIPELINE_FILE_COUNT=1' "$TEST_ROOT/cache-report.txt"
if grep -Fq "$TEST_ROOT" "$TEST_ROOT/cache-report.txt"; then
    print -u2 -- "FAIL: a cache path leaked into the report"
    exit 1
fi
pass_count=$((pass_count + 1))
print -- "PASS: cache snapshots are aggregate-only and deduplicate roots"

zsh -n "$SCRIPT_DIR/capture-metal-performance.sh"
zsh -n "$SCRIPT_DIR/capture-window-cadence.sh"
zsh -n "$CACHE_SNAPSHOT"
pass_count=$((pass_count + 1))
print -- "PASS: performance capture wrappers parse"

SECUNDA_SOURCE_ONLY=1 "$SCRIPT_DIR/capture-metal-performance.sh" --help \
    | grep -Fq 'MTL_HUD_LOG_ENABLED=1'
SECUNDA_SOURCE_ONLY=1 "$SCRIPT_DIR/capture-window-cadence.sh" --help \
    | grep -Fq 'not authoritative GPU present time'
pass_count=$((pass_count + 1))
print -- "PASS: primary and fallback limitations are documented"

print -- "PASS: $pass_count Gate 3 performance-probe contracts verified."
