#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
SOURCE_COLLECTION_ROOT=${SECUNDA_SOURCE_ROOT:-"$REPOSITORY_ROOT/sources"}
SOURCE_ROOT="$SOURCE_COLLECTION_ROOT/wine"
SOURCE_ALIAS=${SECUNDA_WINE_SOURCE_ALIAS:-/private/tmp/secunda-wine-source-x86_64}
DEPLOYMENT_TARGET=${SECUNDA_DEPLOYMENT_TARGET:-15.0}
DEPLOYMENT_KEY=${DEPLOYMENT_TARGET//./_}
if [[ "$DEPLOYMENT_TARGET" != "15.0" ]]; then
    echo "Secunda distribution builds currently require SECUNDA_DEPLOYMENT_TARGET=15.0." >&2
    exit 64
fi
DEPENDENCY_BUILD_ROOT=${SECUNDA_DEPENDENCY_BUILD_ROOT:-"$REPOSITORY_ROOT/build/runtime-dependencies-x86_64-macos$DEPLOYMENT_KEY"}
BUILD_ROOT=${SECUNDA_WINE_BUILD_ROOT:-"$REPOSITORY_ROOT/build/runtime-wine-x86_64-macos$DEPLOYMENT_KEY-release"}
BUILD_ROOT_ALIAS=${SECUNDA_WINE_BUILD_ROOT_ALIAS:-"/private/tmp/secunda-wine-build-x86_64-macos$DEPLOYMENT_KEY-release"}
TOOLCHAIN_ROOT="$REPOSITORY_ROOT/build/toolchain-bin"
STAGE_CONTAINER=$(mktemp -d "${TMPDIR:-/tmp}/secunda-wine-stage.XXXXXX")
INSTALL_PREFIX=/opt/secunda-runtime
STAGE_ROOT="$STAGE_CONTAINER$INSTALL_PREFIX"
RUNTIME_ROOT=${SECUNDA_RUNTIME_OUTPUT:-"$REPOSITORY_ROOT/Runtime/wine"}
RUNTIME_ROOT=${RUNTIME_ROOT:A}
RUNTIME_STAGE=''
DEPS_ROOT=${SECUNDA_DEPENDENCY_PREFIX:-"$DEPENDENCY_BUILD_ROOT/prefix"}
DEPS_ROOT_ALIAS=${SECUNDA_DEPENDENCY_PREFIX_ALIAS:-"/private/tmp/secunda-dependency-prefix-x86_64-macos$DEPLOYMENT_KEY"}
RUNTIME_PATCHES=(
    "$REPOSITORY_ROOT/patches/wine-arm64-d3dmetal-event.patch"
    "$REPOSITORY_ROOT/patches/wine-arm64-metal-layer.patch"
    "$REPOSITORY_ROOT/patches/wine-optional-vulkan-loader.patch"
    "$REPOSITORY_ROOT/patches/wine-secunda-identity.patch"
    "$REPOSITORY_ROOT/patches/wine-clang-syscall-abi.patch"
    "$REPOSITORY_ROOT/patches/wine-secunda-cef-in-process-gpu.patch"
    "$REPOSITORY_ROOT/patches/wine-secunda-rosetta-debug-registers.patch"
    "$REPOSITORY_ROOT/patches/wine-secunda-compat-knobs.patch"
    "$REPOSITORY_ROOT/patches/wine-avrt-mmcss-priority.patch"
    "$REPOSITORY_ROOT/patches/wine-secunda-sdl-controller-bus.patch"
)

cleanup() {
    rm -rf "$STAGE_CONTAINER"
    if [[ -n "${RUNTIME_STAGE:-}" && -d "$RUNTIME_STAGE" ]]; then
        rm -rf "$RUNTIME_STAGE"
    fi
}
trap cleanup EXIT

apply_runtime_patch() {
    local patch_file=$1
    if patch -d "$SOURCE_ROOT" -p1 --dry-run --forward < "$patch_file" >/dev/null 2>&1; then
        patch -d "$SOURCE_ROOT" -p1 --forward < "$patch_file"
        return
    fi
    if patch -d "$SOURCE_ROOT" -p1 --dry-run --reverse < "$patch_file" >/dev/null 2>&1; then
        echo "Already applied: ${patch_file:t}"
        return
    fi
    echo "Patch does not apply cleanly: $patch_file" >&2
    exit 1
}

relocate_runtime_libraries() {
    local runtime_root=$1
    local library_root="$runtime_root/lib"

    install_name_tool -id @rpath/libgmp.10.dylib "$library_root/libgmp.10.dylib"
    install_name_tool -id @rpath/libnettle.8.dylib "$library_root/libnettle.8.9.dylib"
    install_name_tool -id @rpath/libhogweed.6.dylib "$library_root/libhogweed.6.9.dylib"
    install_name_tool -id @rpath/libgnutls.30.dylib "$library_root/libgnutls.30.dylib"

    install_name_tool \
        -change "$DEPS_ROOT_ALIAS/lib/libnettle.8.dylib" @rpath/libnettle.8.dylib \
        -change "$DEPS_ROOT_ALIAS/lib/libgmp.10.dylib" @rpath/libgmp.10.dylib \
        "$library_root/libhogweed.6.9.dylib"
    install_name_tool \
        -change "$DEPS_ROOT_ALIAS/lib/libhogweed.6.dylib" @rpath/libhogweed.6.dylib \
        -change "$DEPS_ROOT_ALIAS/lib/libnettle.8.dylib" @rpath/libnettle.8.dylib \
        -change "$DEPS_ROOT_ALIAS/lib/libgmp.10.dylib" @rpath/libgmp.10.dylib \
        "$library_root/libgnutls.30.dylib"
}

if [[ ! -x "$SOURCE_ROOT/configure" ]]; then
    echo "Wine sources were not found at $SOURCE_ROOT" >&2
    exit 1
fi
mkdir -p "${RUNTIME_ROOT:h}"
if [[ -e "$RUNTIME_ROOT" || -L "$RUNTIME_ROOT" ]]; then
    echo "Refusing to merge a build into an existing runtime: $RUNTIME_ROOT" >&2
    echo "Choose a new SECUNDA_RUNTIME_OUTPUT for an atomic source build." >&2
    exit 1
fi
if [[ -e "$SOURCE_ALIAS" && ! -L "$SOURCE_ALIAS" ]]; then
    echo "Wine source alias is occupied by a non-symlink: $SOURCE_ALIAS" >&2
    exit 1
fi
ln -sfn "$SOURCE_ROOT" "$SOURCE_ALIAS"

for dependency in llvm lld bison; do
    if ! brew --prefix "$dependency" >/dev/null 2>&1; then
        echo "Missing Homebrew build dependency: $dependency" >&2
        exit 1
    fi
done

if ! "$REPOSITORY_ROOT/scripts/verify-runtime-dependencies.sh" \
    "$DEPS_ROOT" "$DEPLOYMENT_TARGET" >/dev/null 2>&1; then
    "$REPOSITORY_ROOT/scripts/build-runtime-dependencies.sh"
fi
"$REPOSITORY_ROOT/scripts/verify-runtime-dependencies.sh" "$DEPS_ROOT" "$DEPLOYMENT_TARGET"
if [[ -e "$DEPS_ROOT_ALIAS" && ! -L "$DEPS_ROOT_ALIAS" ]]; then
    echo "Dependency prefix alias is occupied by a non-symlink: $DEPS_ROOT_ALIAS" >&2
    exit 1
fi
ln -sfn "$DEPS_ROOT" "$DEPS_ROOT_ALIAS"

for runtime_patch in "${RUNTIME_PATCHES[@]}"; do
    apply_runtime_patch "$runtime_patch"
done

LLVM_ROOT=$(brew --prefix llvm)
LLD_ROOT=$(brew --prefix lld)
BISON_ROOT=$(brew --prefix bison)
mkdir -p "$BUILD_ROOT" "$TOOLCHAIN_ROOT" "$STAGE_ROOT"
if [[ -e "$BUILD_ROOT_ALIAS" && ! -L "$BUILD_ROOT_ALIAS" ]]; then
    echo "Wine build alias is occupied by a non-symlink: $BUILD_ROOT_ALIAS" >&2
    exit 1
fi
ln -sfn "$BUILD_ROOT" "$BUILD_ROOT_ALIAS"
ln -sf "$LLVM_ROOT/bin/llvm-dlltool" "$TOOLCHAIN_ROOT/dlltool"
ln -sf "$LLD_ROOT/bin/lld-link" "$TOOLCHAIN_ROOT/lld-link"
export PATH="$TOOLCHAIN_ROOT:$LLVM_ROOT/bin:$LLD_ROOT/bin:$BISON_ROOT/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG_LIBDIR="$DEPS_ROOT_ALIAS/lib/pkgconfig"
export CPPFLAGS="-I$DEPS_ROOT_ALIAS/include -I$DEPS_ROOT_ALIAS/include/freetype2"
export CFLAGS="-O2 -g0 -mmacosx-version-min=$DEPLOYMENT_TARGET -ffile-prefix-map=$SOURCE_ALIAS=/usr/src/secunda/wine"
export CXXFLAGS="$CFLAGS"
export CROSSCFLAGS="-O2 -g0 -ffile-prefix-map=$SOURCE_ALIAS=/usr/src/secunda/wine"
export LDFLAGS="-L$DEPS_ROOT_ALIAS/lib -Wl,-rpath,$DEPS_ROOT_ALIAS/lib -Wl,-ld_classic -mmacosx-version-min=$DEPLOYMENT_TARGET"
export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"

cd "$BUILD_ROOT_ALIAS"
"$SOURCE_ALIAS/configure" \
    --prefix="$INSTALL_PREFIX" \
    --build=x86_64-apple-darwin \
    --enable-archs=i386,x86_64 \
    --disable-tests \
    --with-mingw="$LLVM_ROOT/bin/clang" \
    --without-x \
    --without-vulkan \
    --without-pcap \
    --without-opencl \
    --without-gssapi \
    --without-krb5 \
    --without-cups \
    --without-pcsclite \
    --without-usb \
    BISON="$BISON_ROOT/bin/bison" \
    CC="/usr/bin/clang -arch x86_64" \
    CXX="/usr/bin/clang++ -arch x86_64"

grep -q '#define SONAME_LIBFREETYPE' include/config.h
grep -q '#define SONAME_LIBGNUTLS' include/config.h
# winebus dlopens SDL2 for controller support; without it the macOS IOHID bus
# takes over and only Xbox pads reach XInput.
grep -q '#define SONAME_LIBSDL2' include/config.h

BUILD_JOBS=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)
make -j"$BUILD_JOBS"
make install DESTDIR="$STAGE_CONTAINER"
/usr/bin/clang \
    -arch arm64 \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -mmacosx-version-min="$DEPLOYMENT_TARGET" \
    -O2 \
    -g0 \
    -Wall \
    -Wextra \
    -Werror \
    -I"$SOURCE_ROOT/server" \
    "$REPOSITORY_ROOT/tools/secunda-rosetta-debug-broker.c" \
    -o "$STAGE_ROOT/bin/secunda-rosetta-debug-broker"
RUNTIME_STAGE=$(mktemp -d "${RUNTIME_ROOT:h}/.secunda-runtime-stage.XXXXXX")
ditto "$STAGE_ROOT" "$RUNTIME_STAGE"
chmod 0755 "$RUNTIME_STAGE"
mkdir -p "$RUNTIME_STAGE/lib"
ditto "$DEPS_ROOT/lib" "$RUNTIME_STAGE/lib"
"$REPOSITORY_ROOT/scripts/fetch-dxmt.sh" "$RUNTIME_STAGE"
"$REPOSITORY_ROOT/scripts/fetch-vulkan-stack.sh" "$RUNTIME_STAGE"
mkdir -p "$RUNTIME_STAGE/share/secunda"
cp "$REPOSITORY_ROOT/packaging/runtime-provenance.json" \
    "$RUNTIME_STAGE/share/secunda/runtime-provenance.json"
relocate_runtime_libraries "$RUNTIME_STAGE"

while IFS= read -r -d '' runtime_file; do
    if file "$runtime_file" | grep -q 'Mach-O'; then
        if [[ "$runtime_file" == "$RUNTIME_STAGE/bin/secunda-rosetta-debug-broker" ]]; then
            codesign --force --sign - --options runtime "$runtime_file"
        else
            codesign --force --sign - "$runtime_file"
        fi
    fi
done < <(find "$RUNTIME_STAGE" -type f -print0)

"$REPOSITORY_ROOT/scripts/relocate-runtime.sh" "$RUNTIME_STAGE" --fix
# Relocation re-signs every modified Mach-O. Restore the native relay's
# hardened-runtime option after that final load-command mutation.
codesign --force --sign - --options runtime \
    "$RUNTIME_STAGE/bin/secunda-rosetta-debug-broker"
"$REPOSITORY_ROOT/scripts/verify-runtime-dependencies.sh" \
    "$RUNTIME_STAGE" "$DEPLOYMENT_TARGET" --write-stamp
"$REPOSITORY_ROOT/scripts/stage-runtime-notices.sh" "$RUNTIME_STAGE"
"$REPOSITORY_ROOT/scripts/create-runtime-integrity.sh" "$RUNTIME_STAGE"
SECUNDA_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    "$REPOSITORY_ROOT/scripts/verify-runtime-distribution.sh" "$RUNTIME_STAGE"

"$REPOSITORY_ROOT/scripts/publish-runtime-directory.sh" "$RUNTIME_STAGE" "$RUNTIME_ROOT"
RUNTIME_STAGE=''

echo "Secunda source runtime staged at $RUNTIME_ROOT"
echo "Run scripts/smoke-test-runtime.sh to verify Windows and DirectX 11 on this Mac."
