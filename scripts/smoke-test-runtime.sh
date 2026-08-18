#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
DEPLOYMENT_TARGET=${SECUNDA_DEPLOYMENT_TARGET:-15.0}
DEPLOYMENT_KEY=${DEPLOYMENT_TARGET//./_}
RUNTIME_ROOT=${SECUNDA_RUNTIME_SOURCE:-"$REPOSITORY_ROOT/Runtime/wine"}
RUNTIME_ROOT=${RUNTIME_ROOT:A}
BUILD_ROOT="$REPOSITORY_ROOT/build/runtime-smoke"
WINE_BUILD_ROOT=${SECUNDA_WINE_BUILD_ROOT:-"$REPOSITORY_ROOT/build/runtime-wine-x86_64-macos$DEPLOYMENT_KEY-release"}
SMOKE_PREFIX=$(mktemp -d /private/tmp/secunda-runtime-smoke.XXXXXX)
EXIT_TRACE_PREFIX=$(mktemp -d /private/tmp/secunda-exit-trace-smoke.XXXXXX)
WINE="$RUNTIME_ROOT/bin/wine"
STAGED_WINEGCC="$RUNTIME_ROOT/bin/winegcc"
SOURCE_WINEGCC="$WINE_BUILD_ROOT/tools/winegcc/winegcc"
SMOKE_TIMEOUT_SECONDS=${SECUNDA_SMOKE_TIMEOUT_SECONDS:-30}

if [[ ! -x "$WINE" || ! -x "$RUNTIME_ROOT/bin/wineserver" ]]; then
    echo "The staged runtime is incomplete." >&2
    exit 1
fi

if [[ -x "$STAGED_WINEGCC" ]]; then
    WINEGCC="$STAGED_WINEGCC"
    WINEGCC_PREFIX=(-I"$RUNTIME_ROOT/include")
elif [[ -x "$SOURCE_WINEGCC" ]]; then
    WINEGCC="$SOURCE_WINEGCC"
    WINEGCC_PREFIX=(
        --wine-objdir "$WINE_BUILD_ROOT"
        -I"$WINE_BUILD_ROOT/include"
        -I"$REPOSITORY_ROOT/sources/wine/include"
        -I"$REPOSITORY_ROOT/sources/wine/include/msvcrt"
    )
else
    echo "The staged runtime does not include winegcc." >&2
    exit 1
fi

cleanup() {
    env WINEPREFIX="$SMOKE_PREFIX" "$RUNTIME_ROOT/bin/wineserver" -k >/dev/null 2>&1 || true
    env WINEPREFIX="$EXIT_TRACE_PREFIX" "$RUNTIME_ROOT/bin/wineserver" -k >/dev/null 2>&1 || true
    rm -rf "$SMOKE_PREFIX" "$EXIT_TRACE_PREFIX"
}
trap cleanup EXIT INT TERM

mkdir -p "$BUILD_ROOT"

compile_d3d11_smoke() {
    local target=$1
    local output=$2
    "$WINEGCC" \
        "${WINEGCC_PREFIX[@]}" \
        -b "$target" \
        "$REPOSITORY_ROOT/tools/d3d11-smoke.c" \
        -o "$output" \
        -ld3d11 \
        -lkernel32
}

compile_d3d11_smoke x86_64-windows "$BUILD_ROOT/d3d11-smoke.exe"
compile_d3d11_smoke i386-windows "$BUILD_ROOT/d3d11-smoke-x86.exe"

"$WINEGCC" \
    "${WINEGCC_PREFIX[@]}" \
    -b i386-windows \
    "$REPOSITORY_ROOT/tools/debug-register-smoke.c" \
    -o "$BUILD_ROOT/debug-register-smoke-x86.exe" \
    -lkernel32 \
    -lmsvcrt

"$WINEGCC" \
    "${WINEGCC_PREFIX[@]}" \
    -b i386-windows \
    "$REPOSITORY_ROOT/tools/debug-register-concurrency-smoke.c" \
    -o "$BUILD_ROOT/debug-register-concurrency-smoke-x86.exe" \
    -lkernel32 \
    -lmsvcrt

"$WINEGCC" \
    "${WINEGCC_PREFIX[@]}" \
    -b i386-windows \
    "$REPOSITORY_ROOT/tools/debug-register-polling-smoke.c" \
    -o "$BUILD_ROOT/debug-register-polling-smoke-x86.exe" \
    -lkernel32 \
    -lmsvcrt

"$WINEGCC" \
    "${WINEGCC_PREFIX[@]}" \
    -b i386-windows \
    "$REPOSITORY_ROOT/tools/debug-register-overlap-smoke.c" \
    -o "$BUILD_ROOT/debug-register-overlap-smoke-x86.exe" \
    -lkernel32 \
    -lmsvcrt

"$WINEGCC" \
    "${WINEGCC_PREFIX[@]}" \
    -b i386-windows \
    "$REPOSITORY_ROOT/tools/debug-register-ceg-transition-smoke.c" \
    -o "$BUILD_ROOT/debug-register-ceg-transition-smoke-x86.exe" \
    -lkernel32 \
    -lmsvcrt

"$WINEGCC" \
    "${WINEGCC_PREFIX[@]}" \
    -b i386-windows \
    "$REPOSITORY_ROOT/tools/protected-hash-copy-smoke.c" \
    -o "$BUILD_ROOT/protected-hash-copy-smoke-x86.exe" \
    -Wl,--image-base,0x10000000 \
    -lkernel32 \
    -lmsvcrt

"$WINEGCC" \
    "${WINEGCC_PREFIX[@]}" \
    -b i386-windows \
    "$REPOSITORY_ROOT/tools/exit-import-trace-smoke.c" \
    -o "$BUILD_ROOT/exit-import-trace-smoke-x86.exe" \
    -Wl,--image-base,0x10000000 \
    -Wl,/dynamicbase:no \
    -lkernel32 \
    -lmsvcrt

"$WINEGCC" \
    "${WINEGCC_PREFIX[@]}" \
    -b i386-windows \
    "$REPOSITORY_ROOT/tools/execute-entry-trace-smoke.c" \
    -o "$BUILD_ROOT/execute-entry-trace-smoke-x86.exe" \
    -Wl,--image-base,0x11000000 \
    -Wl,/dynamicbase:no \
    -lkernel32

if ! objdump -d "$BUILD_ROOT/exit-import-trace-smoke-x86.exe" |
    grep 'calll.*\*0x10002284' >/dev/null; then
    echo "Exit-import smoke IAT moved from 0x10002284." >&2
    exit 1
fi

COMMON_ENV=(
    WINEPREFIX="$SMOKE_PREFIX"
    WINEARCH=win64
    WINEMSYNC=1
    WINEDEBUG=-all
    'WINEDLLOVERRIDES=mscoree,mshtml=;winemenubuilder.exe=d;d3d10core,d3d11,dxgi=b'
    DXMT_LOG_LEVEL=info
    DXMT_LOG_PATH="$BUILD_ROOT"
)

run_bounded() {
    local label=$1
    shift
    "$@" &
    local command_pid=$!
    (
        sleep "$SMOKE_TIMEOUT_SECONDS"
        kill -ALRM "$command_pid" 2>/dev/null || true
    ) &
    local watchdog_pid=$!
    local command_status

    if wait "$command_pid"; then
        command_status=0
    else
        command_status=$?
    fi
    kill -TERM "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true

    if (( command_status == 0 )); then
        echo "PASS: $label"
        return 0
    fi
    if (( command_status == 142 )); then
        echo "FAIL: $label exceeded ${SMOKE_TIMEOUT_SECONDS}s." >&2
        return 124
    fi
    echo "FAIL: $label exited with status $command_status." >&2
    return "$command_status"
}

run_exit_import_observer() {
    local log="$BUILD_ROOT/exit-import-trace-smoke.log"
    local command_pid watchdog_pid command_status

    env \
        WINEPREFIX="$EXIT_TRACE_PREFIX" \
        WINEARCH=win64 \
        WINEMSYNC=1 \
        WINEDEBUG=-all,err+seh \
        SECUNDA_DEBUG_RELAY_TRACE=1 \
        SECUNDA_TRACE_EXIT_IAT=0x10002284 \
        'WINEDLLOVERRIDES=mscoree,mshtml=;winemenubuilder.exe=d' \
        "$WINE" "$BUILD_ROOT/exit-import-trace-smoke-x86.exe" >"$log" 2>&1 &
    command_pid=$!
    (
        sleep "$SMOKE_TIMEOUT_SECONDS"
        kill -ALRM "$command_pid" 2>/dev/null || true
    ) &
    watchdog_pid=$!

    if wait "$command_pid"; then
        command_status=0
    else
        command_status=$?
    fi
    kill -TERM "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    sed -n '1,120p' "$log"

    if (( command_status != 37 )); then
        echo "FAIL: exit-import observer returned $command_status instead of 37." >&2
        return 1
    fi
    if ! grep -q 'SECUNDA_EXIT_IMPORT event=read' "$log" ||
       ! grep -Eq 'SECUNDA_EXIT_IMPORT_CONTEXT .*instruction=ff15' "$log" ||
       ! grep -q 'SECUNDA_EXIT_IMPORT_STACK index=0 values=00000025' "$log" ||
       ! grep -q 'SECUNDA_EXIT_IMPORT_FRAME index=0' "$log" ||
       ! grep -q 'EXIT_TRACE_SMOKE stage=import-rewritten' "$log" ||
       (( $(grep -c 'SECUNDA_EXIT_IMPORT_CONTEXT' "$log") != 1 )); then
        echo "FAIL: exit-import observer did not capture the call context and status." >&2
        return 1
    fi
    echo "PASS: non-mutating 32-bit ExitProcess observer"
}

run_execute_entry_observer() {
    local log="$BUILD_ROOT/execute-entry-trace-smoke.log"

    run_bounded "one-shot 32-bit execute-entry observer" env \
        "${COMMON_ENV[@]}" \
        WINEDEBUG=-all,err+seh \
        SECUNDA_TRACE_EXECUTE_ENTRY=0x10040010,0x10040000,0x10040020 \
        "$WINE" "$BUILD_ROOT/execute-entry-trace-smoke-x86.exe" \
        >"$log" 2>&1
    sed -n '1,120p' "$log"
    if ! grep -Eq 'SECUNDA_EXECUTE_ENTRY_ARMED address=10040010 .*targets=3' "$log" ||
       ! grep -Eq 'SECUNDA_EXECUTE_ENTRY_CONTEXT .*eip=10040000 .*return=[0-9a-fA-F]*[1-9a-fA-F][0-9a-fA-F]* .*instruction=b82a000000c3' "$log" ||
       ! grep -q 'EXECUTE_ENTRY_SMOKE stage=returned' "$log" ||
       (( $(grep -c 'SECUNDA_EXECUTE_ENTRY_CONTEXT' "$log") != 1 )); then
        echo "FAIL: execute-entry observer did not capture one intact caller." >&2
        return 1
    fi
    echo "PASS: non-mutating one-shot 32-bit execute-entry observer"
}

run_bounded "Wine command" env "${COMMON_ENV[@]}" "$WINE" cmd.exe /d /c ver
run_bounded "64-bit Direct3D 11" env "${COMMON_ENV[@]}" "$WINE" "$BUILD_ROOT/d3d11-smoke.exe"
run_bounded "32-bit Direct3D 11" env "${COMMON_ENV[@]}" "$WINE" "$BUILD_ROOT/d3d11-smoke-x86.exe"
run_bounded "32-bit debug-register relay" env \
    "${COMMON_ENV[@]}" \
    SECUNDA_DEBUG_RELAY_TRACE=1 \
    "$WINE" "$BUILD_ROOT/debug-register-smoke-x86.exe"
run_bounded "concurrent 32-bit execute breakpoints" env \
    "${COMMON_ENV[@]}" \
    "$WINE" "$BUILD_ROOT/debug-register-concurrency-smoke-x86.exe"
run_bounded "same-page polling with 32-bit execute breakpoint" env \
    "${COMMON_ENV[@]}" \
    "$WINE" "$BUILD_ROOT/debug-register-polling-smoke-x86.exe"
run_bounded "overlapping 32-bit data watchpoint" env \
    "${COMMON_ENV[@]}" \
    SECUNDA_DEBUG_RELAY_TRACE=1 \
    "$WINE" "$BUILD_ROOT/debug-register-overlap-smoke-x86.exe"
run_bounded "CEG-shaped 32-bit debug transition" env \
    "${COMMON_ENV[@]}" \
    SECUNDA_DEBUG_RELAY_TRACE=1 \
    "$WINE" "$BUILD_ROOT/debug-register-ceg-transition-smoke-x86.exe"
run_bounded "protected 32-bit hash copy" env \
    "${COMMON_ENV[@]}" \
    SECUNDA_ROSETTA_PROTECTED_HASH_COPY=1 \
    SECUNDA_ROSETTA_PROTECTED_HASH_COPY_SMOKE=1 \
    SECUNDA_TRACE_PROTECTED_TRANSFORM=1 \
    "$WINE" "$BUILD_ROOT/protected-hash-copy-smoke-x86.exe"
run_exit_import_observer
run_execute_entry_observer

echo "Runtime command, Direct3D, and debug-register smoke tests passed."
echo "Disposable smoke prefixes will be removed on exit."
