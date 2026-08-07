#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
CLASSIFIER="$SCRIPT_DIR/classify-gate3-exit.sh"
MARKER_SCANNER="$REPOSITORY_ROOT/tools/secunda-exit-markers.awk"

driver_path=""
report_path=""
run_count=""
timeout_seconds=""
termination_grace_seconds=5
pause_seconds=2
temporary_root=""
owned_driver_pid=""
owned_scanner_pid=""
owned_watchdog_pid=""
last_acceptance=""
last_classification=""
last_duration_seconds=0
last_exit_code=""
last_fatal_markers=0
last_host_markers=0
last_posix_signal=0
last_timed_out=0
last_windows_markers=0

usage() {
    cat <<'EOF'
Usage:
  SECUNDA_GATE3_ACCEPTANCE=1 ./scripts/run-gate3-repeat-acceptance.sh \
    --driver ABSOLUTE_PATH --runs COUNT --timeout-seconds SECONDS \
    --report FILE [--pause-seconds SECONDS] [--termination-grace-seconds SECONDS]

Runs an operator-supplied, single-run driver a bounded number of times. The
driver must block until its exact target exits and should use exec for that
target. The harness never searches for or signals processes by name. On a
timeout it signals only the exact driver PID it started.

Target output is streamed into a marker scanner. Raw lines are never written to
the report or retained on disk. The report contains duration, normalized exit
status, marker counts, classification, and an aggregate pass/fail verdict.

  --driver PATH                       Executable one-run driver; no arguments.
  --runs COUNT                        1 through 20.
  --timeout-seconds SECONDS           1 through 7200 for each run.
  --report FILE                       Destination; parent must already exist.
  --pause-seconds SECONDS             0 through 60 between runs (default: 2).
  --termination-grace-seconds SECONDS 1 through 30 after TERM (default: 5).
  --help                              Show this help.

The explicit SECUNDA_GATE3_ACCEPTANCE=1 marker prevents accidental execution.
EOF
}

fail() {
    print -u2 -- "GATE 3 REPEAT ACCEPTANCE FAILED: $*"
    exit 2
}

stop_owned_process() {
    local process_id=$1

    [[ -n "$process_id" ]] || return
    if kill -0 "$process_id" 2>/dev/null; then
        kill -TERM "$process_id" 2>/dev/null || true
    fi
    wait "$process_id" 2>/dev/null || true
}

cleanup() {
    stop_owned_process "$owned_watchdog_pid"
    stop_owned_process "$owned_driver_pid"
    stop_owned_process "$owned_scanner_pid"
    if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
        rm -rf -- "$temporary_root"
    fi
}

trap cleanup EXIT INT TERM

field_value() {
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

write_timeout_flag_after_delay() {
    local process_id=$1
    local timeout_flag=$2

    sleep "$timeout_seconds"
    if ! kill -0 "$process_id" 2>/dev/null; then
        return
    fi

    print -r -- 1 > "$timeout_flag"
    kill -TERM "$process_id" 2>/dev/null || return
    sleep "$termination_grace_seconds"
    if kill -0 "$process_id" 2>/dev/null; then
        kill -KILL "$process_id" 2>/dev/null || true
    fi
}

wait_for_scanner() {
    local run_index=$1
    local scanner_timeout_flag=$2
    local scanner_status

    (
        sleep 5
        if kill -0 "$owned_scanner_pid" 2>/dev/null; then
            print -r -- 1 > "$scanner_timeout_flag"
            kill -TERM "$owned_scanner_pid" 2>/dev/null || true
        fi
    ) &
    owned_watchdog_pid=$!

    set +e
    wait "$owned_scanner_pid"
    scanner_status=$?
    set -e
    owned_scanner_pid=""

    stop_owned_process "$owned_watchdog_pid"
    owned_watchdog_pid=""

    [[ ! -f "$scanner_timeout_flag" ]] \
        || fail "run $run_index driver left its output stream open"
    (( scanner_status == 0 )) || fail "run $run_index marker scanner failed"
}

execute_driver() {
    local run_index=$1
    local run_root=$2
    local output_fifo="$run_root/output.fifo"
    local markers_file="$run_root/markers.txt"
    local timeout_flag="$run_root/timed-out"
    local scanner_timeout_flag="$run_root/scanner-timed-out"
    local start_seconds
    local end_seconds

    mkdir -p "$run_root"
    mkfifo "$output_fifo"

    /usr/bin/awk -f "$MARKER_SCANNER" < "$output_fifo" > "$markers_file" &
    owned_scanner_pid=$!

    start_seconds=$(/bin/date +%s)
    SECUNDA_GATE3_RUN_INDEX="$run_index" \
    SECUNDA_GATE3_TIMEOUT_SECONDS="$timeout_seconds" \
        "$driver_path" > "$output_fifo" 2>&1 &
    owned_driver_pid=$!

    write_timeout_flag_after_delay "$owned_driver_pid" "$timeout_flag" &
    owned_watchdog_pid=$!

    set +e
    wait "$owned_driver_pid"
    last_exit_code=$?
    set -e
    owned_driver_pid=""

    stop_owned_process "$owned_watchdog_pid"
    owned_watchdog_pid=""
    [[ -f "$timeout_flag" ]] && last_timed_out=1 || last_timed_out=0

    wait_for_scanner "$run_index" "$scanner_timeout_flag"

    end_seconds=$(/bin/date +%s)
    last_duration_seconds=$(( end_seconds - start_seconds ))
}

load_classification() {
    local run_index=$1
    local markers_file=$2
    local classification_file=$3

    "$CLASSIFIER" \
        --exit-code "$last_exit_code" \
        --markers "$markers_file" \
        --timed-out "$last_timed_out" \
        --run-index "$run_index" \
        > "$classification_file"

    last_classification=$(field_value CLASSIFICATION "$classification_file") \
        || fail "run $run_index classification is incomplete"
    last_acceptance=$(field_value ACCEPTANCE "$classification_file") \
        || fail "run $run_index acceptance is incomplete"
    last_exit_code=$(field_value EXIT_CODE_NORMALIZED "$classification_file") \
        || fail "run $run_index exit status is incomplete"
    last_posix_signal=$(field_value POSIX_SIGNAL "$classification_file") \
        || fail "run $run_index signal status is incomplete"
    last_windows_markers=$(field_value WINDOWS_ACCESS_VIOLATION_MARKERS "$classification_file") \
        || fail "run $run_index Windows marker count is incomplete"
    last_host_markers=$(field_value HOST_CRASH_MARKERS "$classification_file") \
        || fail "run $run_index host marker count is incomplete"
    last_fatal_markers=$(field_value FATAL_RUNTIME_MARKERS "$classification_file") \
        || fail "run $run_index fatal marker count is incomplete"
}

append_run_report() {
    local run_index=$1

    {
        print -r -- "RUN_${run_index}_DURATION_SECONDS=$last_duration_seconds"
        print -r -- "RUN_${run_index}_CLASSIFICATION=$last_classification"
        print -r -- "RUN_${run_index}_ACCEPTANCE=$last_acceptance"
        print -r -- "RUN_${run_index}_EXIT_CODE=$last_exit_code"
        print -r -- "RUN_${run_index}_POSIX_SIGNAL=$last_posix_signal"
        print -r -- "RUN_${run_index}_TIMED_OUT=$last_timed_out"
        print -r -- "RUN_${run_index}_WINDOWS_ACCESS_VIOLATION_MARKERS=$last_windows_markers"
        print -r -- "RUN_${run_index}_HOST_CRASH_MARKERS=$last_host_markers"
        print -r -- "RUN_${run_index}_FATAL_RUNTIME_MARKERS=$last_fatal_markers"
        print -r -- "RUN_${run_index}_RAW_LOG_RETAINED=0"
    } >> "$temporary_root/report.body"
}

run_once() {
    local run_index=$1
    local run_root="$temporary_root/run-$run_index"
    local markers_file="$run_root/markers.txt"
    local classification_file="$run_root/classification.txt"

    execute_driver "$run_index" "$run_root"
    load_classification "$run_index" "$markers_file" "$classification_file"
    append_run_report "$run_index"

    print -- "Run $run_index/$run_count: $last_classification (${last_duration_seconds}s)"
    [[ "$last_acceptance" == "PASS" ]]
}

while (( $# > 0 )); do
    case "$1" in
        --driver)
            (( $# >= 2 )) || fail "--driver requires a path"
            driver_path=$2
            shift 2
            ;;
        --runs)
            (( $# >= 2 )) || fail "--runs requires a count"
            run_count=$2
            shift 2
            ;;
        --timeout-seconds)
            (( $# >= 2 )) || fail "--timeout-seconds requires a value"
            timeout_seconds=$2
            shift 2
            ;;
        --report)
            (( $# >= 2 )) || fail "--report requires a file"
            report_path=$2
            shift 2
            ;;
        --pause-seconds)
            (( $# >= 2 )) || fail "--pause-seconds requires a value"
            pause_seconds=$2
            shift 2
            ;;
        --termination-grace-seconds)
            (( $# >= 2 )) || fail "--termination-grace-seconds requires a value"
            termination_grace_seconds=$2
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

[[ "${SECUNDA_GATE3_ACCEPTANCE:-0}" == "1" ]] \
    || fail "set SECUNDA_GATE3_ACCEPTANCE=1 to authorize bounded execution"
[[ -n "$driver_path" ]] || fail "--driver is required"
[[ "$driver_path" == /* ]] || fail "--driver must be an absolute path"
[[ -x "$driver_path" && -f "$driver_path" ]] || fail "--driver must be an executable regular file"
[[ "$run_count" == <-> ]] || fail "--runs must be a whole number"
(( run_count >= 1 && run_count <= 20 )) || fail "--runs must be from 1 through 20"
[[ "$timeout_seconds" == <-> ]] || fail "--timeout-seconds must be a whole number"
(( timeout_seconds >= 1 && timeout_seconds <= 7200 )) \
    || fail "--timeout-seconds must be from 1 through 7200"
[[ "$pause_seconds" == <-> ]] || fail "--pause-seconds must be a whole number"
(( pause_seconds >= 0 && pause_seconds <= 60 )) \
    || fail "--pause-seconds must be from 0 through 60"
[[ "$termination_grace_seconds" == <-> ]] \
    || fail "--termination-grace-seconds must be a whole number"
(( termination_grace_seconds >= 1 && termination_grace_seconds <= 30 )) \
    || fail "--termination-grace-seconds must be from 1 through 30"
[[ -n "$report_path" ]] || fail "--report is required"
[[ -d "${report_path:h}" ]] || fail "report parent directory does not exist"
[[ -x "$CLASSIFIER" ]] || fail "exit classifier is unavailable"
[[ -f "$MARKER_SCANNER" ]] || fail "marker scanner is unavailable"

driver_path=${driver_path:A}
report_path=${report_path:A}
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/secunda-gate3-repeat.XXXXXX")
: > "$temporary_root/report.body"

clean_runs=0
failed_runs=0
completed_runs=0

for (( run_index = 1; run_index <= run_count; run_index++ )); do
    if run_once "$run_index"; then
        clean_runs=$(( clean_runs + 1 ))
    else
        failed_runs=$(( failed_runs + 1 ))
    fi
    completed_runs=$run_index

    if (( run_index < run_count && pause_seconds > 0 )); then
        sleep "$pause_seconds"
    fi
done

overall_acceptance=FAIL
if (( completed_runs == run_count && clean_runs == run_count )); then
    overall_acceptance=PASS
fi

{
    print -r -- "SECUNDA_GATE3_REPEAT_FORMAT=1"
    print -r -- "CHECKED_AT_UTC=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
    print -r -- "REQUESTED_RUNS=$run_count"
    print -r -- "COMPLETED_RUNS=$completed_runs"
    print -r -- "CLEAN_RUNS=$clean_runs"
    print -r -- "FAILED_RUNS=$failed_runs"
    print -r -- "PER_RUN_TIMEOUT_SECONDS=$timeout_seconds"
    print -r -- "RAW_LOG_POLICY=DISCARDED_AFTER_STREAM_CLASSIFICATION"
    cat "$temporary_root/report.body"
    print -r -- "OVERALL_ACCEPTANCE=$overall_acceptance"
} > "$temporary_root/report.txt"

mv -- "$temporary_root/report.txt" "$report_path"
print -- "Gate 3 repeat report written with privacy-safe classifications only."

[[ "$overall_acceptance" == "PASS" ]] \
    || fail "$failed_runs of $run_count runs were not clean"

print -- "PASS: $clean_runs/$run_count bounded runs exited cleanly."
