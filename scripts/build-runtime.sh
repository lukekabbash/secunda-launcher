#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
SOURCE_ROOT="$REPOSITORY_ROOT/sources/wine"
SOURCE_ALIAS="/private/tmp/secunda-wine-source-x86_64"
BUILD_ROOT="$REPOSITORY_ROOT/build/runtime-wine-x86_64"
TOOLCHAIN_ROOT="$REPOSITORY_ROOT/build/toolchain-bin"
STAGE_ROOT="/private/tmp/secunda-wine-runtime-x86"
RUNTIME_ROOT="$REPOSITORY_ROOT/Runtime/wine"
DEPS_ROOT=${SECUNDA_DEPENDENCY_PREFIX:-"$REPOSITORY_ROOT/build/runtime-dependencies-x86_64/prefix"}
RUNTIME_PATCHES=(
    "$REPOSITORY_ROOT/patches/wine-arm64-d3dmetal-event.patch"
    "$REPOSITORY_ROOT/patches/wine-arm64-metal-layer.patch"
    "$REPOSITORY_ROOT/patches/wine-optional-vulkan-loader.patch"
    "$REPOSITORY_ROOT/patches/wine-secunda-identity.patch"
)

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
        -change "$DEPS_ROOT/lib/libnettle.8.dylib" @rpath/libnettle.8.dylib \
        -change "$DEPS_ROOT/lib/libgmp.10.dylib" @rpath/libgmp.10.dylib \
        "$library_root/libhogweed.6.9.dylib"
    install_name_tool \
        -change "$DEPS_ROOT/lib/libhogweed.6.dylib" @rpath/libhogweed.6.dylib \
        -change "$DEPS_ROOT/lib/libnettle.8.dylib" @rpath/libnettle.8.dylib \
        -change "$DEPS_ROOT/lib/libgmp.10.dylib" @rpath/libgmp.10.dylib \
        "$library_root/libgnutls.30.dylib"
}

if [[ ! -x "$SOURCE_ROOT/configure" ]]; then
    echo "Wine sources were not found at $SOURCE_ROOT" >&2
    exit 1
fi

ln -sfn "$SOURCE_ROOT" "$SOURCE_ALIAS"

for dependency in llvm lld bison; do
    if ! brew --prefix "$dependency" >/dev/null 2>&1; then
        echo "Missing Homebrew build dependency: $dependency" >&2
        exit 1
    fi
done

if [[ ! -f "$DEPS_ROOT/lib/libfreetype.6.dylib" || ! -f "$DEPS_ROOT/lib/libgnutls.30.dylib" ]]; then
    "$REPOSITORY_ROOT/scripts/build-runtime-dependencies.sh"
fi

for runtime_patch in "${RUNTIME_PATCHES[@]}"; do
    apply_runtime_patch "$runtime_patch"
done

LLVM_ROOT=$(brew --prefix llvm)
LLD_ROOT=$(brew --prefix lld)
BISON_ROOT=$(brew --prefix bison)
mkdir -p "$BUILD_ROOT" "$TOOLCHAIN_ROOT" "$STAGE_ROOT" "$RUNTIME_ROOT"
ln -sf "$LLVM_ROOT/bin/llvm-dlltool" "$TOOLCHAIN_ROOT/dlltool"
ln -sf "$LLD_ROOT/bin/lld-link" "$TOOLCHAIN_ROOT/lld-link"
export PATH="$TOOLCHAIN_ROOT:$LLVM_ROOT/bin:$LLD_ROOT/bin:$BISON_ROOT/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG_LIBDIR="$DEPS_ROOT/lib/pkgconfig"
export CPPFLAGS="-I$DEPS_ROOT/include -I$DEPS_ROOT/include/freetype2"
export LDFLAGS="-L$DEPS_ROOT/lib -Wl,-rpath,$DEPS_ROOT/lib -Wl,-ld_classic"

cd "$BUILD_ROOT"
"$SOURCE_ALIAS/configure" \
    --prefix="$STAGE_ROOT" \
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

BUILD_JOBS=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)
make -j"$BUILD_JOBS"
make install
ditto "$STAGE_ROOT" "$RUNTIME_ROOT"
mkdir -p "$RUNTIME_ROOT/lib"
ditto "$DEPS_ROOT/lib" "$RUNTIME_ROOT/lib"
"$REPOSITORY_ROOT/scripts/fetch-dxmt.sh" "$RUNTIME_ROOT"
mkdir -p "$RUNTIME_ROOT/share/secunda"
cp "$REPOSITORY_ROOT/packaging/runtime-provenance.json" \
    "$RUNTIME_ROOT/share/secunda/runtime-provenance.json"
relocate_runtime_libraries "$RUNTIME_ROOT"

while IFS= read -r -d '' runtime_file; do
    if file "$runtime_file" | grep -q 'Mach-O'; then
        codesign --force --sign - "$runtime_file"
    fi
done < <(find "$RUNTIME_ROOT" -type f -print0)

echo "Secunda source runtime staged at $RUNTIME_ROOT"
echo "Run scripts/smoke-test-runtime.sh to verify Windows and DirectX 11 on this Mac."
