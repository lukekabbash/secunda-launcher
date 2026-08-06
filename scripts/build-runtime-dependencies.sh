#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
SOURCE_ROOT="$REPOSITORY_ROOT/sources"
BUILD_ROOT="$REPOSITORY_ROOT/build/runtime-dependencies-x86_64"
PREFIX=${SECUNDA_DEPENDENCY_PREFIX:-"$BUILD_ROOT/prefix"}
NETTLE_VERSION=3.10
NETTLE_ARCHIVE="$BUILD_ROOT/nettle-$NETTLE_VERSION.tar.gz"
NETTLE_SOURCE="$BUILD_ROOT/nettle-$NETTLE_VERSION"
GMP_SOURCE_ALIAS=/private/tmp/secunda-gmp-source-x86_64
GNUTLS_SOURCE_ALIAS=/private/tmp/secunda-gnutls-source-x86_64
NETTLE_SOURCE_ALIAS=/private/tmp/secunda-nettle-source-x86_64
JOBS=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)

build_cmake_dependency() {
    local name=$1
    shift
    cmake "$@"
    cmake --build "$BUILD_ROOT/$name" --parallel "$JOBS"
    cmake --install "$BUILD_ROOT/$name"
}

configure_and_build() {
    local name=$1
    local source=$2
    shift 2
    mkdir -p "$BUILD_ROOT/$name"
    (
        cd "$BUILD_ROOT/$name"
        env \
            CC='/usr/bin/clang -arch x86_64' \
            CFLAGS='-O2 -fPIC' \
            CPPFLAGS="-I$PREFIX/include" \
            LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib -Wl,-ld_classic" \
            PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
            "$source/configure" \
            --prefix="$PREFIX" \
            --build=x86_64-apple-darwin \
            --host=x86_64-apple-darwin \
            "$@"
        if [[ "$name" == "gnutls" ]] && grep -q '^#define ENABLE_GOST' config.h; then
            echo "Refusing to package a GnuTLS build with GOST enabled." >&2
            exit 1
        fi
        if [[ -n "${SECUNDA_MAKE_LIBS:-}" ]]; then
            make -j"$JOBS" LIBS="$SECUNDA_MAKE_LIBS"
            make install LIBS="$SECUNDA_MAKE_LIBS"
        else
            make -j"$JOBS"
            make install
        fi
    )
}

mkdir -p "$BUILD_ROOT" "$PREFIX"
ln -sfn "$SOURCE_ROOT/gnutls/gmp" "$GMP_SOURCE_ALIAS"
ln -sfn "$SOURCE_ROOT/gnutls/gnutls" "$GNUTLS_SOURCE_ALIAS"

build_cmake_dependency freetype \
    -S "$SOURCE_ROOT/freetype" \
    -B "$BUILD_ROOT/freetype" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DBUILD_SHARED_LIBS=ON \
    -DFT_DISABLE_ZLIB=ON \
    -DFT_DISABLE_BZIP2=ON \
    -DFT_DISABLE_PNG=ON \
    -DFT_DISABLE_HARFBUZZ=ON \
    -DFT_DISABLE_BROTLI=ON \
    -DCMAKE_INSTALL_NAME_DIR=@rpath

configure_and_build gmp "$GMP_SOURCE_ALIAS" \
    --disable-static \
    --enable-shared

if [[ ! -f "$NETTLE_SOURCE/Makefile.in" ]]; then
    curl --fail --location --retry 3 \
        --output "$NETTLE_ARCHIVE" \
        "https://ftp.gnu.org/gnu/nettle/nettle-$NETTLE_VERSION.tar.gz"
    tar -xzf "$NETTLE_ARCHIVE" -C "$BUILD_ROOT"
fi
ln -sfn "$NETTLE_SOURCE" "$NETTLE_SOURCE_ALIAS"

configure_and_build nettle "$NETTLE_SOURCE_ALIAS" \
    --disable-static \
    --enable-shared \
    --disable-documentation

SECUNDA_MAKE_LIBS='-lhogweed -lnettle -lgmp' \
configure_and_build gnutls "$GNUTLS_SOURCE_ALIAS" \
    --disable-static \
    --enable-shared \
    --disable-doc \
    --disable-tools \
    --disable-tests \
    --disable-cxx \
    --disable-nls \
    --disable-libdane \
    --disable-gost \
    --without-p11-kit \
    --without-tpm2 \
    --without-tpm \
    --without-zlib \
    --without-brotli \
    --without-zstd \
    --without-idn \
    --with-default-trust-store-file=/etc/ssl/cert.pem \
    --with-included-libtasn1 \
    --with-included-unistring

file "$PREFIX/lib/libfreetype.6.dylib" \
    "$PREFIX/lib/libgmp.10.dylib" \
    "$PREFIX/lib/libnettle.8.dylib" \
    "$PREFIX/lib/libhogweed.6.dylib" \
    "$PREFIX/lib/libgnutls.30.dylib"

echo "Secunda x86_64 runtime dependencies staged at $PREFIX"
