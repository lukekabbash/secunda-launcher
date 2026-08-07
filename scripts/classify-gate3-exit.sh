#!/bin/zsh -f
set -euo pipefail
setopt extended_glob

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
MARKER_SCANNER="$REPOSITORY_ROOT/tools/secunda-exit-markers.awk"

exit_code="unknown"
log_path=""
markers_path=""
run_index=0
timed_out=0
temporary_root=""

usage() {
    cat <<'EOF'
Usage:
  ./scripts/classify-gate3-exit.sh \
    [--exit-code CODE] (--log FILE | --markers FILE) \
    [--timed-out 0|1] [--run-index NUMBER]

Classifies one completed run without reproducing raw output. The report contains
only normalized marker counts, exit information, and a verdict. It never emits
input lines, file paths, commands, arguments, or environment values.

  --exit-code CODE  0, a POSIX status, a Windows status, or "unknown".
  --log FILE        Completed regular log file to scan privately.
  --markers FILE    Pre-sanitized marker file produced by the marker scanner.
  --timed-out 0|1   Whether the bounded runner ended the run for timeout.
  --run-index N     Optional non-negative run number for report correlation.
  --help            Show this help.
EOF
}

fail() {
    print -u2 -- "GATE 3 EXIT CLASSIFIER FAILED: $*"
    exit 2
}

cleanup() {
    if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
        rm -rf -- "$temporary_root"
    fi
}

trap cleanup EXIT

marker_value() {
    local key=$1
    local file=$2

    /usr/bin/awk -F= -v key="$key" '
        $1 == key {
            print substr($0, index($0, "=") + 1)
            found = 1
            exit
        }
        END { if (!found) exit 1 }
    ' "$file"
}

while (( $# > 0 )); do
    case "$1" in
        --exit-code)
            (( $# >= 2 )) || fail "--exit-code requires a value"
            exit_code=$2
            shift 2
            ;;
        --log)
            (( $# >= 2 )) || fail "--log requires a file"
            log_path=$2
            shift 2
            ;;
        --markers)
            (( $# >= 2 )) || fail "--markers requires a file"
            markers_path=$2
            shift 2
            ;;
        --timed-out)
            (( $# >= 2 )) || fail "--timed-out requires 0 or 1"
            timed_out=$2
            shift 2
            ;;
        --run-index)
            (( $# >= 2 )) || fail "--run-index requires a number"
            run_index=$2
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

[[ -f "$MARKER_SCANNER" ]] || fail "marker scanner is unavailable"
[[ "$timed_out" == "0" || "$timed_out" == "1" ]] \
    || fail "--timed-out must be 0 or 1"
[[ "$run_index" == <-> ]] || fail "--run-index must be a non-negative integer"

if [[ -n "$log_path" && -n "$markers_path" ]]; then
    fail "provide --log or --markers, not both"
fi
if [[ -z "$log_path" && -z "$markers_path" ]]; then
    fail "provide --log or --markers"
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/secunda-exit-classifier.XXXXXX")
if [[ -n "$log_path" ]]; then
    [[ -f "$log_path" && -r "$log_path" ]] || fail "--log must be a readable regular file"
    markers_path="$temporary_root/markers.txt"
    /usr/bin/awk -f "$MARKER_SCANNER" "$log_path" > "$markers_path"
else
    [[ -f "$markers_path" && -r "$markers_path" ]] \
        || fail "--markers must be a readable regular file"
fi

grep -Fxq 'SECUNDA_EXIT_MARKERS_FORMAT=1' "$markers_path" \
    || fail "marker file format is invalid"

windows_markers=$(marker_value WINDOWS_ACCESS_VIOLATION_MARKERS "$markers_path") \
    || fail "marker file lacks the Windows access-violation count"
host_markers=$(marker_value HOST_CRASH_MARKERS "$markers_path") \
    || fail "marker file lacks the host-crash count"
fatal_markers=$(marker_value FATAL_RUNTIME_MARKERS "$markers_path") \
    || fail "marker file lacks the fatal-runtime count"

for count in "$windows_markers" "$host_markers" "$fatal_markers"; do
    [[ "$count" == <-> ]] || fail "marker counts must be non-negative integers"
done

normalized_exit_code=${exit_code:l}
normalized_exit_code=${normalized_exit_code//[[:space:]]/}
exit_code_present=1
exit_code_is_zero=0
exit_code_is_access_violation=0
posix_signal=0

case "$normalized_exit_code" in
    unknown|none|missing|'')
        normalized_exit_code=unknown
        exit_code_present=0
        ;;
    0|0x0|0x00000000)
        normalized_exit_code=0
        exit_code_is_zero=1
        ;;
    c0000005|0xc0000005|3221225477|-1073741819)
        normalized_exit_code=0xC0000005
        exit_code_is_access_violation=1
        ;;
    <->)
        if (( normalized_exit_code >= 129 && normalized_exit_code <= 192 )); then
            posix_signal=$(( normalized_exit_code - 128 ))
        fi
        ;;
    -<->|0x[0-9a-f]##|[0-9a-f]##)
        ;;
    *)
        fail "--exit-code is not a supported numeric status"
        ;;
esac

classification=INDETERMINATE
acceptance=FAIL

if (( windows_markers > 0 || exit_code_is_access_violation )); then
    classification=WINDOWS_ACCESS_VIOLATION
elif (( host_markers > 0 )); then
    classification=HOST_PROCESS_CRASH
elif (( fatal_markers > 0 )); then
    classification=FATAL_RUNTIME_ERROR
elif (( timed_out )); then
    classification=TIMEOUT
elif (( posix_signal > 0 )); then
    classification=HOST_SIGNAL_EXIT
elif (( exit_code_is_zero )); then
    classification=CLEAN_EXIT
    acceptance=PASS
elif (( exit_code_present )); then
    classification=NONZERO_EXIT
fi

print -r -- "SECUNDA_EXIT_CLASSIFICATION_FORMAT=1"
print -r -- "RUN_INDEX=$run_index"
print -r -- "CLASSIFICATION=$classification"
print -r -- "ACCEPTANCE=$acceptance"
print -r -- "EXIT_CODE_PRESENT=$exit_code_present"
print -r -- "EXIT_CODE_NORMALIZED=$normalized_exit_code"
print -r -- "POSIX_SIGNAL=$posix_signal"
print -r -- "TIMED_OUT=$timed_out"
print -r -- "WINDOWS_ACCESS_VIOLATION_MARKERS=$windows_markers"
print -r -- "HOST_CRASH_MARKERS=$host_markers"
print -r -- "FATAL_RUNTIME_MARKERS=$fatal_markers"
print -r -- "RAW_LOG_REPRODUCED=0"
