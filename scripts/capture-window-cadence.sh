#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
CADENCE_PROBE="$REPOSITORY_ROOT/tools/window-frame-cadence.swift"
WINDOW_PROBE="$REPOSITORY_ROOT/tools/secunda-window-probe.swift"
PROVENANCE_VERIFIER="$SCRIPT_DIR/verify-source-only-provenance.sh"

runtime_path=""
process_id=""
window_id=""
report_path=""
duration_seconds=15
target_fps=60
temporary_root=""

usage() {
    cat <<'EOF'
Usage:
  SECUNDA_SOURCE_ONLY=1 ./scripts/capture-window-cadence.sh \
    --runtime PATH --pid PID --window-id ID --report FILE \
    [--duration SECONDS] [--target-fps FPS]

Samples one exact moving Skyrim window through macOS ScreenCaptureKit without
saving pixels. This is a bounded fallback for a process that was not launched
with Metal Performance HUD logging. It reports approximate compositor delivery
and visual-change cadence, not authoritative GPU present time or GPU workload.

Run it while the scene is visibly moving. A static menu or paused game cannot
produce useful visual-change cadence. Screen Recording permission may be needed
for the shell or host app executing this developer probe.

  --runtime PATH     Exact source-built Wine executable used for the run.
  --pid PID          Exact Skyrim process ID.
  --window-id ID     Exact visible Skyrim macOS window ID.
  --report FILE      Destination report; its parent must already exist.
  --duration SECONDS Capture duration from 5 through 60 (default: 15).
  --target-fps FPS   Comparison budget from 1 through 240 (default: 60).
  --help             Show this help.
EOF
}

fail() {
    print -u2 -- "WINDOW CADENCE CAPTURE FAILED: $*"
    exit 1
}

cleanup() {
    if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
        rm -rf -- "$temporary_root"
    fi
}

trap cleanup EXIT

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
    && (( duration_seconds >= 5 && duration_seconds <= 60 )) \
    || fail "--duration must be from 5 through 60 seconds"
[[ "$target_fps" == <-> ]] \
    && (( target_fps >= 1 && target_fps <= 240 )) \
    || fail "--target-fps must be from 1 through 240"
ps -p "$process_id" -o pid= >/dev/null 2>&1 || fail "process is not running"

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/secunda-window-cadence.XXXXXX")
runtime_path=${runtime_path:A}
report_path=${report_path:A}

env -i \
    HOME="$HOME" \
    LANG="${LANG:-en_US.UTF-8}" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="${TMPDIR:-/tmp}" \
    CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/secunda-window-cadence-clang-cache" \
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

env -i \
    HOME="$HOME" \
    LANG="${LANG:-en_US.UTF-8}" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="${TMPDIR:-/tmp}" \
    CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/secunda-window-cadence-clang-cache" \
    /usr/bin/swift "$CADENCE_PROBE" \
    --pid "$process_id" \
    --window-id "$window_id" \
    --duration "$duration_seconds" \
    --target-fps "$target_fps" \
    --report "$temporary_root/cadence.txt"

{
    print -r -- "SECUNDA_WINDOW_CADENCE_ACCEPTANCE_FORMAT=1"
    print -r -- "CHECKED_AT_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    print -r -- "SECUNDA_SOURCE_ONLY=1"
    print -r -- "RUNTIME_EXECUTABLE=$runtime_path"
    print -r -- "WINDOW_IDENTITY_BEGIN"
    cat "$temporary_root/window.txt"
    print -r -- "WINDOW_IDENTITY_END"
    cat "$temporary_root/cadence.txt"
    print -r -- "SOURCE_ONLY_PROVENANCE_BEGIN"
    cat "$temporary_root/provenance.txt"
    print -r -- "SOURCE_ONLY_PROVENANCE_END"
} > "$temporary_root/report.txt"

cp -- "$temporary_root/report.txt" "$report_path"
print -- "Window cadence report: $report_path"

grep -Fq 'CAPTURE_RESULT=PASS' "$report_path" \
    || fail "the compositor sampler did not receive enough frames"
if grep -Fq 'MOTION_SIGNAL=LOW' "$report_path"; then
    print -u2 -- "WARNING: little visual motion was observed; repeat during active gameplay."
fi
