#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR=${0:A:h}
CLASSIFIER="$SCRIPT_DIR/classify-gate3-exit.sh"
REPEAT_HARNESS="$SCRIPT_DIR/run-gate3-repeat-acceptance.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-gate3-test.XXXXXX")
pass_count=0

cleanup() {
    rm -rf -- "$TEST_ROOT"
}

trap cleanup EXIT

expect_classification() {
    local expected=$1
    local exit_code=$2
    local fixture=$3
    local output="$TEST_ROOT/classification.txt"

    "$CLASSIFIER" --exit-code "$exit_code" --log "$fixture" > "$output"
    grep -Fxq "CLASSIFICATION=$expected" "$output"
    pass_count=$(( pass_count + 1 ))
    print -- "PASS: $expected classification"
}

expect_failure() {
    local label=$1
    shift

    if "$@" > "$TEST_ROOT/failure.stdout" 2> "$TEST_ROOT/failure.stderr"; then
        print -u2 -- "FAIL: expected rejection: $label"
        exit 1
    fi
    pass_count=$(( pass_count + 1 ))
    print -- "PASS: $label"
}

mkdir -p "$TEST_ROOT/fixtures" "$TEST_ROOT/drivers" "$TEST_ROOT/reports"

print -- 'ordinary shutdown completed' > "$TEST_ROOT/fixtures/clean.log"
print -- 'ABNORMAL 0xC0000005 after synthetic interaction' \
    > "$TEST_ROOT/fixtures/windows-access-violation.log"
print -- 'wine: Unhandled page fault on read access at address 0000000000000000' \
    > "$TEST_ROOT/fixtures/wine-page-fault.log"
print -- 'exception type: EXC_BAD_ACCESS (SIGSEGV)' \
    > "$TEST_ROOT/fixtures/host-crash.log"
print -- 'fatal runtime error: invariant failed' \
    > "$TEST_ROOT/fixtures/fatal.log"
print -- 'trace:seh:dispatch_exception code=c0000005 flags=0' \
    > "$TEST_ROOT/fixtures/first-chance.log"

expect_classification CLEAN_EXIT 0 "$TEST_ROOT/fixtures/clean.log"
expect_classification WINDOWS_ACCESS_VIOLATION 5 \
    "$TEST_ROOT/fixtures/windows-access-violation.log"
expect_classification WINDOWS_ACCESS_VIOLATION unknown \
    "$TEST_ROOT/fixtures/wine-page-fault.log"
expect_classification HOST_PROCESS_CRASH 1 "$TEST_ROOT/fixtures/host-crash.log"
expect_classification FATAL_RUNTIME_ERROR 1 "$TEST_ROOT/fixtures/fatal.log"
expect_classification WINDOWS_ACCESS_VIOLATION 0xC0000005 \
    "$TEST_ROOT/fixtures/clean.log"
expect_classification HOST_SIGNAL_EXIT 139 "$TEST_ROOT/fixtures/clean.log"
expect_classification CLEAN_EXIT 0 "$TEST_ROOT/fixtures/first-chance.log"

print -- 'account=do-not-record password=do-not-record /Users/private/input' \
    > "$TEST_ROOT/fixtures/private.log"
"$CLASSIFIER" --exit-code 0 --log "$TEST_ROOT/fixtures/private.log" \
    > "$TEST_ROOT/private-classification.txt"
if grep -Eq 'do-not-record|/Users/private|private[.]log' "$TEST_ROOT/private-classification.txt"; then
    print -u2 -- 'FAIL: classifier reproduced private input'
    exit 1
fi
pass_count=$(( pass_count + 1 ))
print -- 'PASS: classifier output is privacy-safe'

print '#!/bin/zsh -f\nprint -- "account=do-not-record path=/Users/private"\nexit 0' \
    > "$TEST_ROOT/drivers/clean"
print '#!/bin/zsh -f\nprint -- "wine: Unhandled page fault on read access"\nexit 5' \
    > "$TEST_ROOT/drivers/access-violation"
print '#!/bin/zsh -f\nexec /bin/sleep 5' \
    > "$TEST_ROOT/drivers/timeout"
chmod +x "$TEST_ROOT/drivers/clean" \
    "$TEST_ROOT/drivers/access-violation" \
    "$TEST_ROOT/drivers/timeout"

SECUNDA_GATE3_ACCEPTANCE=1 "$REPEAT_HARNESS" \
    --driver "$TEST_ROOT/drivers/clean" \
    --runs 2 \
    --timeout-seconds 2 \
    --termination-grace-seconds 1 \
    --pause-seconds 0 \
    --report "$TEST_ROOT/reports/clean.txt"

grep -Fxq 'COMPLETED_RUNS=2' "$TEST_ROOT/reports/clean.txt"
grep -Fxq 'CLEAN_RUNS=2' "$TEST_ROOT/reports/clean.txt"
grep -Fxq 'OVERALL_ACCEPTANCE=PASS' "$TEST_ROOT/reports/clean.txt"
if grep -Eq 'do-not-record|/Users/private|drivers/clean' "$TEST_ROOT/reports/clean.txt"; then
    print -u2 -- 'FAIL: repeat report reproduced driver output or path'
    exit 1
fi
pass_count=$(( pass_count + 1 ))
print -- 'PASS: two-run clean acceptance and privacy contract'

expect_failure \
    'access violation fails acceptance' \
    env SECUNDA_GATE3_ACCEPTANCE=1 "$REPEAT_HARNESS" \
    --driver "$TEST_ROOT/drivers/access-violation" \
    --runs 1 \
    --timeout-seconds 2 \
    --termination-grace-seconds 1 \
    --pause-seconds 0 \
    --report "$TEST_ROOT/reports/access-violation.txt"
grep -Fxq 'RUN_1_CLASSIFICATION=WINDOWS_ACCESS_VIOLATION' \
    "$TEST_ROOT/reports/access-violation.txt"
pass_count=$(( pass_count + 1 ))
print -- 'PASS: access violation preserved as normalized evidence'

expect_failure \
    'timeout fails acceptance' \
    env SECUNDA_GATE3_ACCEPTANCE=1 "$REPEAT_HARNESS" \
    --driver "$TEST_ROOT/drivers/timeout" \
    --runs 1 \
    --timeout-seconds 1 \
    --termination-grace-seconds 1 \
    --pause-seconds 0 \
    --report "$TEST_ROOT/reports/timeout.txt"
grep -Fxq 'RUN_1_CLASSIFICATION=TIMEOUT' "$TEST_ROOT/reports/timeout.txt"
grep -Fxq 'RUN_1_TIMED_OUT=1' "$TEST_ROOT/reports/timeout.txt"
pass_count=$(( pass_count + 1 ))
print -- 'PASS: timeout is bounded and classified separately'

expect_failure \
    'explicit execution marker is mandatory' \
    env -u SECUNDA_GATE3_ACCEPTANCE "$REPEAT_HARNESS" \
    --driver "$TEST_ROOT/drivers/clean" \
    --runs 1 \
    --timeout-seconds 1 \
    --report "$TEST_ROOT/reports/no-marker.txt"

expect_failure \
    'repeat count has a hard upper bound' \
    env SECUNDA_GATE3_ACCEPTANCE=1 "$REPEAT_HARNESS" \
    --driver "$TEST_ROOT/drivers/clean" \
    --runs 21 \
    --timeout-seconds 1 \
    --report "$TEST_ROOT/reports/too-many.txt"

print -- "PASS: $pass_count Gate 3 crash and repeatability contracts verified."
