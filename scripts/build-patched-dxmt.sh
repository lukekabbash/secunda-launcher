#!/bin/zsh
# Rebuild DXMT v0.80 with the Skyrim startup patch and install the 64-bit
# d3d11.dll into a Secunda Wine runtime.
#
# Stock v0.80 aborts Skyrim SE with "Pure virtual function called" after it
# sets the display mode. patches/dxmt-v0.80-destroyed-object-release.patch is
# the v0.80 form of the fix already on DXMT main (3Shain/dxmt#231).
# patches/dxmt-v0.80-metal-atomic-fetch-add.patch is the one-line shader
# change DXMT main already has, required because current Metal toolchains
# reject v0.80's private __metal_atomic_fetch_add_explicit call.
#
# The first run builds LLVM 15 (x86_64) into ~/Library/Caches/secunda-dxmt-v080.
# Later runs reuse it.
#
#   scripts/build-patched-dxmt.sh [RUNTIME_ROOT]
#
# patches/dxmt-v0.80-precise-math-switch.patch adds DXMT_AIRCONV_PRECISE=1,
# which translates shaders without fast-math flags. Secunda sets it only for
# Skyrim's experimental outdoor shadows.
#
# RUNTIME_ROOT defaults to ./Runtime/wine. lib/wine/x86_64-windows/d3d11.dll
# and lib/wine/x86_64-unix/winemetal.so are replaced. The version marker
# stays 0.80.
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
RUNTIME_ROOT=${1:-"$REPOSITORY_ROOT/Runtime/wine"}
CACHE=${SECUNDA_DXMT_CACHE:-"$HOME/Library/Caches/secunda-dxmt-v080"}
MINGW="$CACHE/toolchains/llvm-mingw-20251216-ucrt-macos-universal"
LLVM="$CACHE/toolchains/llvm-darwin"
DXMT="$CACHE/dxmt"
DESTROYED_PATCH="$REPOSITORY_ROOT/patches/dxmt-v0.80-destroyed-object-release.patch"
METAL_PATCH="$REPOSITORY_ROOT/patches/dxmt-v0.80-metal-atomic-fetch-add.patch"
PRECISE_PATCH="$REPOSITORY_ROOT/patches/dxmt-v0.80-precise-math-switch.patch"

if [[ ! -f "$RUNTIME_ROOT/lib/wine/x86_64-windows/d3d11.dll" ]]; then
    echo "Runtime is missing lib/wine/x86_64-windows/d3d11.dll: $RUNTIME_ROOT" >&2
    exit 1
fi
if [[ ! -x "$RUNTIME_ROOT/bin/winebuild" ]]; then
    echo "Runtime is missing bin/winebuild: $RUNTIME_ROOT" >&2
    exit 1
fi
if [[ ! -x "$MINGW/bin/x86_64-w64-mingw32-gcc" ]]; then
    echo "llvm-mingw is not in $MINGW. See THIRD_PARTY_SOURCES.md." >&2
    exit 1
fi

if [[ ! -f "$LLVM/lib/libLLVMCore.a" ]]; then
    echo "Building LLVM 15 for x86_64. This is the slow step."
    cmake -B "$CACHE/toolchains/llvm-darwin-build" -S "$CACHE/toolchains/llvm-project/llvm" \
        -DCMAKE_INSTALL_PREFIX="$LLVM" \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 \
        -DLLVM_HOST_TRIPLE=x86_64-apple-darwin \
        -DLLVM_ENABLE_ASSERTIONS=On \
        -DLLVM_ENABLE_ZSTD=Off \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_TARGETS_TO_BUILD="" \
        -DLLVM_BUILD_TOOLS=Off \
        -DBUG_REPORT_URL="https://github.com/3Shain/dxmt" \
        -DPACKAGE_VENDOR="DXMT" \
        -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off \
        -G Ninja
    cmake --build "$CACHE/toolchains/llvm-darwin-build"
    cmake --install "$CACHE/toolchains/llvm-darwin-build"
fi

if [[ ! -d "$DXMT/src/d3d11" ]]; then
    git clone --depth 1 --branch v0.80 --recurse-submodules https://github.com/3Shain/dxmt.git "$DXMT"
fi
if ! grep -q "destroyed resource" "$DXMT/src/d3d11/d3d11_resource.hpp"; then
    git -C "$DXMT" apply "$DESTROYED_PATCH"
fi
if grep -q "__metal_atomic_fetch_add_explicit" "$DXMT/src/airconv/shaders/air_tessellation.metal"; then
    git -C "$DXMT" apply "$METAL_PATCH"
fi
if ! grep -q "DXMT_AIRCONV_PRECISE" "$DXMT/src/airconv/nt/dxbc_converter_base.cpp"; then
    git -C "$DXMT" apply "$PRECISE_PATCH"
fi
# The native helper (winemetal.so) carries the shader converter, so it is
# rebuilt too, and must load on the runtime's macOS 15 floor.
export MACOSX_DEPLOYMENT_TARGET=${SECUNDA_DEPLOYMENT_TARGET:-15.0}

export PATH="$MINGW/bin:$PATH"
if [[ ! -f "$DXMT/build/build.ninja" ]]; then
    # Meson treats the first path as the source tree unless setup runs from it.
    (
        cd "$DXMT"
        meson setup --cross-file build-win64.txt \
            -Denable_nvapi=true \
            -Denable_nvngx=true \
            -Dnative_llvm_path="$LLVM" \
            -Dwine_install_path="$RUNTIME_ROOT" \
            build \
            --buildtype release \
            --prefix "$DXMT/install" \
            --strip
    )
fi
meson compile -C "$DXMT/build"
meson install -C "$DXMT/build"

built="$DXMT/install/x86_64-windows/d3d11.dll"
if [[ ! -f "$built" ]]; then
    echo "Patched d3d11.dll was not installed at $built" >&2
    find "$DXMT/install" -name 'd3d11.dll' -print >&2 || true
    exit 1
fi
install -m 0644 "$built" "$RUNTIME_ROOT/lib/wine/x86_64-windows/d3d11.dll"
built_helper="$DXMT/install/x86_64-unix/winemetal.so"
helper_floor=$(vtool -show-build "$built_helper" | awk '/minos/{print $2; exit}')
if [[ "$helper_floor" != "$MACOSX_DEPLOYMENT_TARGET" ]]; then
    echo "winemetal.so targets macOS $helper_floor, expected $MACOSX_DEPLOYMENT_TARGET. Rebuild it after:" >&2
    echo "  ninja -C \"$DXMT/build\" -t clean src/winemetal/unix/winemetal.so" >&2
    exit 1
fi
install -m 0755 "$built_helper" "$RUNTIME_ROOT/lib/wine/x86_64-unix/winemetal.so"
echo "0.80" > "$RUNTIME_ROOT/lib/wine/.secunda-dxmt-version"
echo "Installed patched DXMT v0.80 d3d11.dll into $RUNTIME_ROOT"
