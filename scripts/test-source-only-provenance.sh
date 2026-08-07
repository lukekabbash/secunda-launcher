#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
VERIFIER="$SCRIPT_DIR/verify-source-only-provenance.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-provenance-test.XXXXXX")
pass_count=0
expected_runtime=""

cleanup() {
    rm -rf -- "$TEST_ROOT"
}

trap cleanup EXIT

expect_pass() {
    local name=$1
    shift
    if "$@" > "$TEST_ROOT/last.stdout" 2> "$TEST_ROOT/last.stderr"; then
        pass_count=$((pass_count + 1))
        print -- "PASS: $name"
        return
    fi

    print -u2 -- "FAIL: expected success: $name"
    cat "$TEST_ROOT/last.stderr" >&2
    exit 1
}

expect_fail() {
    local name=$1
    shift
    if "$@" > "$TEST_ROOT/last.stdout" 2> "$TEST_ROOT/last.stderr"; then
        print -u2 -- "FAIL: expected rejection: $name"
        cat "$TEST_ROOT/last.stdout" >&2
        exit 1
    fi

    pass_count=$((pass_count + 1))
    print -- "PASS: $name"
}

mkdir -p "$TEST_ROOT/open-runtime/bin" "$TEST_ROOT/reports"
print '#!/bin/zsh\nexit 0' > "$TEST_ROOT/open-runtime/bin/wine64"
chmod +x "$TEST_ROOT/open-runtime/bin/wine64"

print 'SECUNDA_SOURCE_ONLY=1\nLOADED_PATH=/usr/lib/libSystem.B.dylib' \
    > "$TEST_ROOT/clean-evidence.txt"

expect_pass \
    "clean source runtime and evidence" \
    env SECUNDA_SOURCE_ONLY=1 \
    "$VERIFIER" \
    --runtime "$TEST_ROOT/open-runtime/bin/wine64" \
    --evidence "$TEST_ROOT/clean-evidence.txt" \
    --report "$TEST_ROOT/reports/provenance.txt"

expected_runtime="${TEST_ROOT:A}/open-runtime/bin/wine64"
grep -Fq "RUNTIME_EXECUTABLE=$expected_runtime" \
    "$TEST_ROOT/reports/provenance.txt"
pass_count=$((pass_count + 1))
print -- "PASS: report records resolved runtime executable"

expect_fail \
    "missing explicit source-only mode" \
    env -u SECUNDA_SOURCE_ONLY \
    "$VERIFIER" --evidence "$TEST_ROOT/clean-evidence.txt"

print 'LOADED_PATH=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/libwine.dylib' \
    > "$TEST_ROOT/crossover-evidence.txt"
expect_fail \
    "CrossOver application load path" \
    env SECUNDA_SOURCE_ONLY=1 \
    "$VERIFIER" --evidence "$TEST_ROOT/crossover-evidence.txt"

print 'LOADED_PATH=/private/runtime/lib64/apple_gptk/external/libd3dshared.dylib' \
    > "$TEST_ROOT/gptk-evidence.txt"
expect_fail \
    "GPTK and d3dshared payload path" \
    env SECUNDA_SOURCE_ONLY=1 \
    "$VERIFIER" --evidence "$TEST_ROOT/gptk-evidence.txt"

print 'LOADED_PATH=/private/runtime/D3DMetal.framework/Versions/A/D3DMetal' \
    > "$TEST_ROOT/d3dmetal-evidence.txt"
expect_fail \
    "D3DMetal framework path" \
    env SECUNDA_SOURCE_ONLY=1 \
    "$VERIFIER" --evidence "$TEST_ROOT/d3dmetal-evidence.txt"

print '#!/bin/zsh\n# com.codeweavers.CrossOver.wineloader\nexit 0' \
    > "$TEST_ROOT/open-runtime/bin/vendor-identity-wine64"
chmod +x "$TEST_ROOT/open-runtime/bin/vendor-identity-wine64"
expect_fail \
    "CrossOver identity embedded in runtime executable" \
    env SECUNDA_SOURCE_ONLY=1 \
    "$VERIFIER" --runtime "$TEST_ROOT/open-runtime/bin/vendor-identity-wine64"

mkdir -p "$TEST_ROOT/CrossOver.app/Contents/SharedSupport/CrossOver/bin"
print '#!/bin/zsh\nexit 0' \
    > "$TEST_ROOT/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64"
chmod +x "$TEST_ROOT/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64"
ln -s "$TEST_ROOT/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64" \
    "$TEST_ROOT/disguised-wine64"
expect_fail \
    "symlink resolving into CrossOver" \
    env SECUNDA_SOURCE_ONLY=1 \
    "$VERIFIER" --runtime "$TEST_ROOT/disguised-wine64"

expect_fail \
    "CrossOver-specific environment variable" \
    env SECUNDA_SOURCE_ONLY=1 SECUNDA_CROSSOVER_APP=/Applications/CrossOver.app \
    "$VERIFIER" --evidence "$TEST_ROOT/clean-evidence.txt"

expect_fail \
    "empty evidence is not acceptance" \
    env SECUNDA_SOURCE_ONLY=1 \
    "$VERIFIER" --evidence "$TEST_ROOT/empty-evidence.txt"

print -- "PASS: $pass_count source-only provenance contracts verified."
