#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
HUD_PROBE="$REPOSITORY_ROOT/tools/metal-hud-probe.swift"
WINDOW_PROBE="$REPOSITORY_ROOT/tools/secunda-window-probe.swift"
PROVENANCE_VERIFIER="$SCRIPT_DIR/verify-source-only-provenance.sh"
CACHE_SNAPSHOT="$SCRIPT_DIR/snapshot-dxmt-cache.sh"

runtime_path=""
process_id=""
window_id=""
report_path=""
shader_cache_directory=""
metal_cache_directory=""
duration_seconds=30
target_fps=60
temporary_root=""

usage() {
    cat <<'EOF'
Usage:
  SECUNDA_SOURCE_ONLY=1 ./scripts/capture-metal-performance.sh \
    --runtime PATH --pid PID --window-id ID --report FILE \
    [--duration SECONDS] [--target-fps FPS] \
    [--shader-cache-dir PATH] [--metal-cache-dir PATH]

Captures Apple Metal Performance HUD data for one exact process/window and
reduces it to privacy-safe frame-pacing, GPU-time, memory, and shader-cache
statistics. It never reads process arguments or environments and never emits
raw unified-log events or shader names.

The target process must have been launched with:

  MTL_HUD_ENABLED=1
  MTL_HUD_LOG_ENABLED=1
  MTL_HUD_OPACITY=0.0

For a separate shader-cache characterization run, also add:

  MTL_HUD_LOG_SHADER_ENABLED=1

Shader logging can add overhead, so do not use that extra switch for the clean
frame-pacing acceptance run. The helper only observes an existing process; it
does not launch, stop, focus, or interact with the game.

  --runtime PATH     Exact source-built Wine executable used for the run.
  --pid PID          Exact Skyrim process ID.
  --window-id ID     Exact visible Skyrim macOS window ID.
  --report FILE      Destination report; its parent must already exist.
  --duration SECONDS Capture duration from 5 through 120 (default: 30).
  --target-fps FPS   Comparison budget from 1 through 240 (default: 60).
  --shader-cache-dir PATH  DXMT shader DB root to summarize.
  --metal-cache-dir PATH   Per-game com.apple.metal root to summarize.
  --help             Show this help.
EOF
}

fail() {
    print -u2 -- "METAL PERFORMANCE CAPTURE FAILED: $*"
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

while (( $# > 0 )); do
    case "$1" in
        --runtime)
            (( $# >= 2 )) || fail "--runtime requires a path"
            runtime_path=$2
            shift 2
            ;;
        --pid)
            (( $# >= 2 )) || fail "--pid requires a process ID"
            process_id=$2
            shift 2
            ;;
        --window-id)
            (( $# >= 2 )) || fail "--window-id requires an ID"
            window_id=$2
            shift 2
            ;;
        --report)
            (( $# >= 2 )) || fail "--report requires a path"
            report_path=$2
            shift 2
            ;;
        --duration)
            (( $# >= 2 )) || fail "--duration requires seconds"
            duration_seconds=$2
            shift 2
            ;;
        --target-fps)
            (( $# >= 2 )) || fail "--target-fps requires a value"
            target_fps=$2
            shift 2
            ;;
        --shader-cache-dir)
            (( $# >= 2 )) || fail "--shader-cache-dir requires a path"
            shader_cache_directory=$2
            shift 2
            ;;
        --metal-cache-dir)
            (( $# >= 2 )) || fail "--metal-cache-dir requires a path"
            metal_cache_directory=$2
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
[[ -n "$runtime_path" && -x "$runtime_path" ]] || fail "--runtime must be an executable path"
[[ "$process_id" == <-> ]] && (( process_id > 0 )) || fail "--pid must be a positive integer"
[[ "$window_id" == <-> ]] && (( window_id > 0 )) || fail "--window-id must be a positive integer"
[[ -n "$report_path" ]] || fail "--report is required"
[[ -d "${report_path:h}" ]] || fail "report parent directory does not exist"
[[ "$duration_seconds" == <-> ]] \
    && (( duration_seconds >= 5 && duration_seconds <= 120 )) \
    || fail "--duration must be from 5 through 120 seconds"
[[ "$target_fps" == <-> ]] \
    && (( target_fps >= 1 && target_fps <= 240 )) \
    || fail "--target-fps must be from 1 through 240"
ps -p "$process_id" -o pid= >/dev/null 2>&1 || fail "process is not running"

require_command /usr/bin/log
require_command /usr/bin/swift

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/secunda-metal-performance.XXXXXX")
runtime_path=${runtime_path:A}
report_path=${report_path:A}
typeset -a cache_snapshot_arguments
if [[ -n "$shader_cache_directory" ]]; then
    cache_snapshot_arguments+=(--shader-root "${shader_cache_directory:A}")
fi
if [[ -n "$metal_cache_directory" ]]; then
    cache_snapshot_arguments+=(--metal-root "${metal_cache_directory:A}")
fi

env -i \
    HOME="$HOME" \
    LANG="${LANG:-en_US.UTF-8}" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="${TMPDIR:-/tmp}" \
    CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/secunda-metal-performance-clang-cache" \
    /usr/bin/swift "$WINDOW_PROBE" --pid "$process_id" \
    > "$temporary_root/window.txt"

grep -Eq \
    "^WINDOW id=$window_id owner_pid=$process_id .*title_class=skyrim .*onscreen=1 .*layer=0 " \
    "$temporary_root/window.txt" \
    || fail "the exact window is not an onscreen Skyrim window owned by the PID"

env -i \
    HOME="$HOME" \
    LANG="${LANG:-en_US.UTF-8}" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="${TMPDIR:-/tmp}" \
    SECUNDA_SOURCE_ONLY=1 \
    "$PROVENANCE_VERIFIER" \
    --runtime "$runtime_path" \
    --pid "$process_id" \
    --report "$temporary_root/provenance.txt" \
    > "$temporary_root/provenance.stdout" \
    2> "$temporary_root/provenance.stderr" \
    || fail "source-only provenance verification failed"

env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    "$CACHE_SNAPSHOT" --label BEFORE "${cache_snapshot_arguments[@]}" \
    > "$temporary_root/cache-before.txt"

set +e
env -i \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /usr/bin/log stream \
    --process "$process_id" \
    --style ndjson \
    --level debug \
    --predicate 'subsystem == "com.apple.metal.hud" OR eventMessage BEGINSWITH "metal-HUD:"' \
    --timeout "${duration_seconds}s" \
    > "$temporary_root/metal-hud.ndjson" \
    2> "$temporary_root/log.stderr"
log_exit_code=$?
set -e

env -i \
    HOME="$HOME" \
    LANG="${LANG:-en_US.UTF-8}" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="${TMPDIR:-/tmp}" \
    CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/secunda-metal-performance-clang-cache" \
    /usr/bin/swift "$HUD_PROBE" \
    --input "$temporary_root/metal-hud.ndjson" \
    --pid "$process_id" \
    --window-id "$window_id" \
    --target-fps "$target_fps" \
    --report "$temporary_root/hud-report.txt"

env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    "$CACHE_SNAPSHOT" --label AFTER "${cache_snapshot_arguments[@]}" \
    > "$temporary_root/cache-after.txt"

{
    print -r -- "SECUNDA_METAL_PERFORMANCE_ACCEPTANCE_FORMAT=1"
    print -r -- "CHECKED_AT_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    print -r -- "SECUNDA_SOURCE_ONLY=1"
    print -r -- "RUNTIME_EXECUTABLE=$runtime_path"
    print -r -- "CAPTURE_DURATION_SECONDS=$duration_seconds"
    print -r -- "LOG_STREAM_EXIT_CODE=$log_exit_code"
    print -r -- "WINDOW_IDENTITY_BEGIN"
    cat "$temporary_root/window.txt"
    print -r -- "WINDOW_IDENTITY_END"
    cat "$temporary_root/cache-before.txt"
    cat "$temporary_root/hud-report.txt"
    cat "$temporary_root/cache-after.txt"
    print -r -- "SOURCE_ONLY_PROVENANCE_BEGIN"
    cat "$temporary_root/provenance.txt"
    print -r -- "SOURCE_ONLY_PROVENANCE_END"
} > "$temporary_root/report.txt"

cp -- "$temporary_root/report.txt" "$report_path"
print -- "Metal performance report: $report_path"

grep -Fq 'FRAME_DATA_RESULT=PASS' "$report_path" || fail \
    "no Metal HUD frames arrived; relaunch the target with the documented MTL_HUD variables"
