#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
PROVENANCE_VERIFIER="$SCRIPT_DIR/verify-source-only-provenance.sh"
WINDOW_PROBE="$REPOSITORY_ROOT/tools/secunda-window-probe.swift"

typeset -a process_ids
typeset -a provenance_arguments

runtime_path=""
report_path=""
sample_count=5
sample_interval=1
temporary_root=""
sampling_failed=0

usage() {
    cat <<'EOF'
Usage:
  SECUNDA_SOURCE_ONLY=1 ./scripts/capture-gate-observability.sh \
    --runtime PATH --pid PID [--pid PID]... --report FILE \
    [--samples COUNT] [--interval SECONDS]

Captures a bounded, read-only acceptance snapshot for exact caller-supplied
processes. The report contains process identity, executable path, mapped code
and libraries, title-redacted macOS window metadata, CPU/RSS samples, and the
existing source-only contamination verdict.

The helper never reads or records process arguments or environments. Window
titles are reduced to skyrim, steam, generic, or absent before output.

  --runtime PATH     Exact source-built Wine executable used for the run.
  --pid PID          Exact live process to observe. Repeatable.
  --report FILE      Destination report; its parent directory must exist.
  --samples COUNT    CPU/RSS sample count, 1 through 60 (default: 5).
  --interval SECONDS Whole seconds between samples, 0 through 10 (default: 1).
  --help             Show this help.

One invocation is capped at 60 seconds. Repeat it for longer stability runs.
EOF
}

fail() {
    print -u2 -- "GATE OBSERVABILITY FAILED: $*"
    exit 1
}

cleanup() {
    if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
        rm -rf -- "$temporary_root"
    fi
}

trap cleanup EXIT

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

canonical_path() {
    print -r -- "${1:A}"
}

capture_loaded_paths() {
    local process_id=$1
    local output_path=$2
    local raw_path="$temporary_root/lsof-$process_id.txt"

    /usr/sbin/lsof -n -P -a -p "$process_id" -Ffn > "$raw_path" 2>/dev/null \
        || fail "could not inspect mapped files for PID $process_id"

    awk -v process_id="$process_id" '
        /^f/ {
            mapped = ($0 == "ftxt" || $0 == "fmem")
            next
        }
        /^n/ && mapped {
            path = substr($0, 2)
            lower = tolower(path)
            if (lower ~ /\.(dylib|so([.][0-9]+)*|bundle|dll|exe|aot)$/ ||
                lower ~ /[.]framework\// ||
                lower ~ /\/wine(server)?$/ ||
                lower ~ /\/rosetta\/runtime$/) {
                print "LOADED_PATH pid=" process_id " path=" path
            }
        }
    ' "$raw_path" | LC_ALL=C sort -u > "$output_path"

    [[ -s "$output_path" ]] \
        || fail "no mapped executable or library paths were captured for PID $process_id"
}

sample_processes() {
    local output_path=$1
    local sample_index
    local process_id
    local metrics
    local cpu_percent
    local rss_kib

    : > "$output_path"
    for (( sample_index = 1; sample_index <= sample_count; sample_index++ )); do
        for process_id in "${process_ids[@]}"; do
            metrics=$(ps -p "$process_id" -o %cpu=,rss= 2>/dev/null || true)
            metrics=${metrics##[[:space:]]#}
            if [[ -z "$metrics" ]]; then
                print -r -- "SAMPLE_UNAVAILABLE index=$sample_index pid=$process_id" >> "$output_path"
                sampling_failed=1
                continue
            fi
            read -r cpu_percent rss_kib <<< "$metrics"
            print -r -- \
                "SAMPLE index=$sample_index pid=$process_id cpu_percent=$cpu_percent rss_kib=$rss_kib" \
                >> "$output_path"
        done

        if (( sample_index < sample_count && sample_interval > 0 )); then
            sleep "$sample_interval"
        fi
    done
}

while (( $# > 0 )); do
    case "$1" in
        --runtime)
            (( $# >= 2 )) || fail "--runtime requires a path"
            runtime_path=$2
            shift 2
            ;;
        --pid)
            (( $# >= 2 )) || fail "--pid requires a process ID"
            process_ids+=("$2")
            shift 2
            ;;
        --report)
            (( $# >= 2 )) || fail "--report requires a path"
            report_path=$2
            shift 2
            ;;
        --samples)
            (( $# >= 2 )) || fail "--samples requires a count"
            sample_count=$2
            shift 2
            ;;
        --interval)
            (( $# >= 2 )) || fail "--interval requires whole seconds"
            sample_interval=$2
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

[[ "${SECUNDA_SOURCE_ONLY:-0}" == "1" ]] \
    || fail "set SECUNDA_SOURCE_ONLY=1 before capturing acceptance evidence"
[[ -n "$runtime_path" ]] || fail "--runtime is required"
[[ -x "$runtime_path" ]] || fail "runtime is not executable: $runtime_path"
(( ${#process_ids} > 0 )) || fail "provide at least one --pid"
[[ -n "$report_path" ]] || fail "--report is required"
[[ -d "${report_path:h}" ]] || fail "report parent directory does not exist: ${report_path:h}"
[[ "$sample_count" == <-> ]] || fail "--samples must be a whole number"
(( sample_count >= 1 && sample_count <= 60 )) || fail "--samples must be from 1 through 60"
[[ "$sample_interval" == <-> ]] || fail "--interval must be a whole number"
(( sample_interval >= 0 && sample_interval <= 10 )) || fail "--interval must be from 0 through 10"
(( (sample_count - 1) * sample_interval <= 60 )) \
    || fail "sample duration must not exceed 60 seconds"

require_command /usr/bin/swift
require_command /usr/sbin/lsof
require_command ps

typeset -A seen_process_ids
typeset -a unique_process_ids
for process_id in "${process_ids[@]}"; do
    [[ "$process_id" == <-> ]] || fail "PID must be numeric: $process_id"
    (( process_id > 0 )) || fail "PID must be positive: $process_id"
    [[ -z "${seen_process_ids[$process_id]:-}" ]] || continue
    seen_process_ids[$process_id]=1
    unique_process_ids+=("$process_id")
done
process_ids=("${unique_process_ids[@]}")

for process_id in "${process_ids[@]}"; do
    ps -p "$process_id" -o pid= >/dev/null 2>&1 \
        || fail "process is not running: $process_id"
done

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/secunda-observability.XXXXXX")
runtime_path=$(canonical_path "$runtime_path")
report_path=$(canonical_path "$report_path")

typeset -a window_arguments
for process_id in "${process_ids[@]}"; do
    window_arguments+=(--pid "$process_id")
done

env -i \
    HOME="$HOME" \
    LANG="${LANG:-en_US.UTF-8}" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="${TMPDIR:-/tmp}" \
    CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/secunda-observability-clang-cache" \
    /usr/bin/swift "$WINDOW_PROBE" "${window_arguments[@]}" \
    > "$temporary_root/process-windows.txt"

: > "$temporary_root/loaded-paths.txt"
for process_id in "${process_ids[@]}"; do
    capture_loaded_paths "$process_id" "$temporary_root/loaded-$process_id.txt"
    cat "$temporary_root/loaded-$process_id.txt" >> "$temporary_root/loaded-paths.txt"
    provenance_arguments+=(--pid "$process_id")
done

contamination_result=FAIL
if env -i \
    HOME="$HOME" \
    LANG="${LANG:-en_US.UTF-8}" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="${TMPDIR:-/tmp}" \
    SECUNDA_SOURCE_ONLY=1 \
    "$PROVENANCE_VERIFIER" \
    --runtime "$runtime_path" \
    "${provenance_arguments[@]}" \
    --report "$temporary_root/provenance.txt" \
    > "$temporary_root/provenance.stdout" \
    2> "$temporary_root/provenance.stderr"; then
    contamination_result=PASS
fi

sample_processes "$temporary_root/samples.txt"

{
    print -r -- "SECUNDA_OBSERVABILITY_FORMAT=1"
    print -r -- "CHECKED_AT_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    print -r -- "SECUNDA_SOURCE_ONLY=1"
    print -r -- "RUNTIME_EXECUTABLE=$runtime_path"
    print -r -- "SAMPLE_COUNT=$sample_count"
    print -r -- "SAMPLE_INTERVAL_SECONDS=$sample_interval"
    cat "$temporary_root/process-windows.txt"
    cat "$temporary_root/loaded-paths.txt"
    cat "$temporary_root/samples.txt"
    print -r -- "CONTAMINATION_RESULT=$contamination_result"
    if [[ -f "$temporary_root/provenance.txt" ]]; then
        print -r -- "SOURCE_ONLY_PROVENANCE_BEGIN"
        cat "$temporary_root/provenance.txt"
        print -r -- "SOURCE_ONLY_PROVENANCE_END"
    fi
} > "$temporary_root/report.txt"

cp -- "$temporary_root/report.txt" "$report_path"
print -- "Gate observability report: $report_path"

[[ "$contamination_result" == "PASS" ]] \
    || fail "source-only contamination verifier rejected the observed process set"
(( sampling_failed == 0 )) \
    || fail "one or more observed processes exited during sampling; the partial report was preserved"

print -- "PASS: process, window, resource, and source-only evidence captured."
