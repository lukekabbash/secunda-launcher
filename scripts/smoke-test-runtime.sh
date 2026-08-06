#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
RUNTIME_ROOT="$REPOSITORY_ROOT/Runtime/wine"
BUILD_ROOT="$REPOSITORY_ROOT/build/runtime-smoke"
WINE_BUILD_ROOT="$REPOSITORY_ROOT/build/runtime-wine-x86_64"
SMOKE_PREFIX=$(mktemp -d /private/tmp/secunda-runtime-smoke.XXXXXX)
WINE="$RUNTIME_ROOT/bin/wine"
WINEGCC="$WINE_BUILD_ROOT/tools/winegcc/winegcc"

if [[ ! -x "$WINE" || ! -x "$WINEGCC" ]]; then
    echo "The staged runtime or source build is incomplete." >&2
    exit 1
fi

mkdir -p "$BUILD_ROOT"
"$WINEGCC" \
    --wine-objdir "$WINE_BUILD_ROOT" \
    -b x86_64-windows \
    -I"$WINE_BUILD_ROOT/include" \
    -I"$REPOSITORY_ROOT/sources/wine/include" \
    -I"$REPOSITORY_ROOT/sources/wine/include/msvcrt" \
    "$REPOSITORY_ROOT/tools/d3d11-smoke.c" \
    -o "$BUILD_ROOT/d3d11-smoke.exe" \
    -ld3d11 \
    -lkernel32

COMMON_ENV=(
    WINEPREFIX="$SMOKE_PREFIX"
    WINEARCH=win64
    DYLD_LIBRARY_PATH="$RUNTIME_ROOT/lib"
    WINEDEBUG=-all
    'WINEDLLOVERRIDES=mscoree,mshtml=;winemenubuilder.exe=d;d3d10core,d3d11,dxgi=b'
    DXMT_LOG_LEVEL=info
    DXMT_LOG_PATH="$BUILD_ROOT"
)

env "${COMMON_ENV[@]}" "$WINE" cmd.exe /d /c ver
env "${COMMON_ENV[@]}" "$WINE" "$BUILD_ROOT/d3d11-smoke.exe"
env WINEPREFIX="$SMOKE_PREFIX" "$RUNTIME_ROOT/bin/wineserver" -k

echo "Runtime command and Direct3D smoke tests passed."
echo "Disposable prefix: $SMOKE_PREFIX"
