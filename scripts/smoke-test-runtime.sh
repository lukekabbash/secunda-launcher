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
WINE="$RUNTIME_ROOT/bin/wine"
WINEGCC="$WINE_BUILD_ROOT/tools/winegcc/winegcc"

if [[ ! -x "$WINE" || ! -x "$WINEGCC" ]]; then
    echo "The staged runtime or source build is incomplete." >&2
    exit 1
fi

mkdir -p "$BUILD_ROOT"

compile_d3d11_smoke() {
    local target=$1
    local output=$2
    "$WINEGCC" \
        --wine-objdir "$WINE_BUILD_ROOT" \
        -b "$target" \
        -I"$WINE_BUILD_ROOT/include" \
        -I"$REPOSITORY_ROOT/sources/wine/include" \
        -I"$REPOSITORY_ROOT/sources/wine/include/msvcrt" \
        "$REPOSITORY_ROOT/tools/d3d11-smoke.c" \
        -o "$output" \
        -ld3d11 \
        -lkernel32
}

compile_d3d11_smoke x86_64-windows "$BUILD_ROOT/d3d11-smoke.exe"
compile_d3d11_smoke i386-windows "$BUILD_ROOT/d3d11-smoke-x86.exe"

"$WINEGCC" \
    --wine-objdir "$WINE_BUILD_ROOT" \
    -b i386-windows \
    -I"$WINE_BUILD_ROOT/include" \
    -I"$REPOSITORY_ROOT/sources/wine/include" \
    -I"$REPOSITORY_ROOT/sources/wine/include/msvcrt" \
    "$REPOSITORY_ROOT/tools/debug-register-smoke.c" \
    -o "$BUILD_ROOT/debug-register-smoke-x86.exe" \
    -lkernel32 \
    -lmsvcrt

COMMON_ENV=(
    WINEPREFIX="$SMOKE_PREFIX"
    WINEARCH=win64
    WINEMSYNC=1
    WINEDEBUG=-all
    'WINEDLLOVERRIDES=mscoree,mshtml=;winemenubuilder.exe=d;d3d10core,d3d11,dxgi=b'
    DXMT_LOG_LEVEL=info
    DXMT_LOG_PATH="$BUILD_ROOT"
)

env "${COMMON_ENV[@]}" "$WINE" cmd.exe /d /c ver
env "${COMMON_ENV[@]}" "$WINE" "$BUILD_ROOT/d3d11-smoke.exe"
env "${COMMON_ENV[@]}" "$WINE" "$BUILD_ROOT/d3d11-smoke-x86.exe"
env "${COMMON_ENV[@]}" "$WINE" "$BUILD_ROOT/debug-register-smoke-x86.exe"
env WINEPREFIX="$SMOKE_PREFIX" "$RUNTIME_ROOT/bin/wineserver" -k

echo "Runtime command and 64-bit/32-bit Direct3D smoke tests passed."
echo "Disposable prefix: $SMOKE_PREFIX"
