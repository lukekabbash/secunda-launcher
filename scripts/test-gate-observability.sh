#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR=${0:A:h}
CAPTURE="$SCRIPT_DIR/capture-gate-observability.sh"
WINDOW_PROBE="${SCRIPT_DIR:h}/tools/secunda-window-probe.swift"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-observability-test.XXXXXX")
fixture_pid=""
pass_count=0

cleanup() {
    if [[ -n "$fixture_pid" ]] && ps -p "$fixture_pid" -o pid= >/dev/null 2>&1; then
        kill "$fixture_pid" 2>/dev/null || true
        wait "$fixture_pid" 2>/dev/null || true
    fi
    rm -rf -- "$TEST_ROOT"
}

trap cleanup EXIT

expect_failure() {
    local label=$1
    shift
    if "$@" > "$TEST_ROOT/failure.stdout" 2> "$TEST_ROOT/failure.stderr"; then
        print -u2 -- "FAIL: expected rejection: $label"
        exit 1
    fi
    pass_count=$((pass_count + 1))
    print -- "PASS: $label"
}

mkdir -p "$TEST_ROOT/runtime/bin" "$TEST_ROOT/reports"
print '#!/bin/zsh\nexit 0' > "$TEST_ROOT/runtime/bin/wine"
chmod +x "$TEST_ROOT/runtime/bin/wine"

env -i \
    OBSERVABILITY_SECRET_ENV=do-not-record \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /usr/bin/perl -e 'sleep 120' do-not-record-argument &
fixture_pid=$!

/usr/bin/swift "$WINDOW_PROBE" --self-test
pass_count=$((pass_count + 1))

SECUNDA_SOURCE_ONLY=1 "$CAPTURE" \
    --runtime "$TEST_ROOT/runtime/bin/wine" \
    --pid "$fixture_pid" \
    --pid "$fixture_pid" \
    --samples 2 \
    --interval 0 \
    --report "$TEST_ROOT/reports/observability.txt"

report="$TEST_ROOT/reports/observability.txt"
grep -Fq 'SECUNDA_OBSERVABILITY_FORMAT=1' "$report"
grep -Fq "PROCESS pid=$fixture_pid" "$report"
grep -Fq "WINDOW_NONE pid=$fixture_pid" "$report"
grep -Fq "SAMPLE index=2 pid=$fixture_pid" "$report"
grep -Fq 'CONTAMINATION_RESULT=PASS' "$report"
grep -Fq 'SOURCE_ONLY_PROVENANCE_BEGIN' "$report"
grep -Fq 'LOADED_PATH pid=' "$report"
pass_count=$((pass_count + 1))
print -- "PASS: complete bounded report"

if grep -Fq 'do-not-record' "$report"; then
    print -u2 -- "FAIL: report leaked a process argument or environment value"
    exit 1
fi
pass_count=$((pass_count + 1))
print -- "PASS: process arguments and environment remain private"

expect_failure \
    "explicit source-only marker is mandatory" \
    env -u SECUNDA_SOURCE_ONLY "$CAPTURE" \
    --runtime "$TEST_ROOT/runtime/bin/wine" \
    --pid "$fixture_pid" \
    --report "$TEST_ROOT/reports/no-marker.txt"

expect_failure \
    "dead PID is rejected" \
    env SECUNDA_SOURCE_ONLY=1 "$CAPTURE" \
    --runtime "$TEST_ROOT/runtime/bin/wine" \
    --pid 999999 \
    --report "$TEST_ROOT/reports/dead-pid.txt"

expect_failure \
    "sampling duration is bounded" \
    env SECUNDA_SOURCE_ONLY=1 "$CAPTURE" \
    --runtime "$TEST_ROOT/runtime/bin/wine" \
    --pid "$fixture_pid" \
    --samples 60 \
    --interval 10 \
    --report "$TEST_ROOT/reports/too-long.txt"

print -- "PASS: $pass_count gate observability contracts verified."
