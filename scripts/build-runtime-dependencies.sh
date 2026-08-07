#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
SOURCE_ROOT=${SECUNDA_SOURCE_ROOT:-"$REPOSITORY_ROOT/sources"}
DEPLOYMENT_TARGET=${SECUNDA_DEPLOYMENT_TARGET:-15.0}
DEPLOYMENT_KEY=${DEPLOYMENT_TARGET//./_}
BUILD_ROOT=${SECUNDA_DEPENDENCY_BUILD_ROOT:-"$REPOSITORY_ROOT/build/runtime-dependencies-x86_64-macos$DEPLOYMENT_KEY"}
BUILD_ROOT_ALIAS=${SECUNDA_DEPENDENCY_BUILD_ROOT_ALIAS:-"/private/tmp/secunda-dependency-build-x86_64-macos$DEPLOYMENT_KEY"}
SOURCE_CACHE_ROOT=${SECUNDA_SOURCE_CACHE_ROOT:-"$REPOSITORY_ROOT/build/source-cache"}
PREFIX=${SECUNDA_DEPENDENCY_PREFIX:-"$BUILD_ROOT/prefix"}
PREFIX_ALIAS=${SECUNDA_DEPENDENCY_PREFIX_ALIAS:-"/private/tmp/secunda-dependency-prefix-x86_64-macos$DEPLOYMENT_KEY"}
NETTLE_VERSION=3.10
NETTLE_SHA256=b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c
NETTLE_ARCHIVE="$SOURCE_CACHE_ROOT/nettle-$NETTLE_VERSION.tar.gz"
NETTLE_SOURCE="$BUILD_ROOT/nettle-$NETTLE_VERSION-${NETTLE_SHA256[1,12]}"
FREETYPE_SOURCE_ALIAS=${SECUNDA_FREETYPE_SOURCE_ALIAS:-/private/tmp/secunda-freetype-source-x86_64}
GMP_SOURCE_ALIAS=${SECUNDA_GMP_SOURCE_ALIAS:-/private/tmp/secunda-gmp-source-x86_64}
GNUTLS_SOURCE_ALIAS=${SECUNDA_GNUTLS_SOURCE_ALIAS:-/private/tmp/secunda-gnutls-source-x86_64}
NETTLE_SOURCE_ALIAS=${SECUNDA_NETTLE_SOURCE_ALIAS:-/private/tmp/secunda-nettle-source-x86_64}
JOBS=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)

if [[ "$DEPLOYMENT_TARGET" != "15.0" ]]; then
    echo "Secunda distribution builds currently require SECUNDA_DEPLOYMENT_TARGET=15.0." >&2
    exit 64
fi

build_cmake_dependency() {
    local name=$1
    shift
    cmake "$@"
    cmake --build "$BUILD_ROOT_ALIAS/$name" --parallel "$JOBS"
    cmake --install "$BUILD_ROOT_ALIAS/$name"
}

configure_and_build() {
    local name=$1
    local source=$2
    shift 2
    mkdir -p "$BUILD_ROOT/$name"
    (
        cd "$BUILD_ROOT_ALIAS/$name"
        env \
            CC='/usr/bin/clang -arch x86_64' \
            CFLAGS="-O2 -g0 -fPIC -mmacosx-version-min=$DEPLOYMENT_TARGET -ffile-prefix-map=$source=/usr/src/secunda/$name" \
            CPPFLAGS="-I$PREFIX_ALIAS/include" \
            LDFLAGS="-L$PREFIX_ALIAS/lib -Wl,-rpath,$PREFIX_ALIAS/lib -Wl,-ld_classic -mmacosx-version-min=$DEPLOYMENT_TARGET" \
            MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
            PKG_CONFIG_LIBDIR="$PREFIX_ALIAS/lib/pkgconfig" \
            "$source/configure" \
            --prefix="$PREFIX_ALIAS" \
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

mkdir -p "$BUILD_ROOT" "$SOURCE_CACHE_ROOT" "$PREFIX"
if [[ -e "$BUILD_ROOT_ALIAS" && ! -L "$BUILD_ROOT_ALIAS" ]]; then
    echo "Dependency build alias is occupied by a non-symlink: $BUILD_ROOT_ALIAS" >&2
    exit 1
fi
ln -sfn "$BUILD_ROOT" "$BUILD_ROOT_ALIAS"
if [[ -e "$PREFIX_ALIAS" && ! -L "$PREFIX_ALIAS" ]]; then
    echo "Dependency prefix alias is occupied by a non-symlink: $PREFIX_ALIAS" >&2
    exit 1
fi
ln -sfn "$PREFIX" "$PREFIX_ALIAS"
ln -sfn "$SOURCE_ROOT/freetype" "$FREETYPE_SOURCE_ALIAS"
ln -sfn "$SOURCE_ROOT/gnutls/gmp" "$GMP_SOURCE_ALIAS"
ln -sfn "$SOURCE_ROOT/gnutls/gnutls" "$GNUTLS_SOURCE_ALIAS"

build_cmake_dependency freetype \
    -S "$FREETYPE_SOURCE_ALIAS" \
    -B "$BUILD_ROOT_ALIAS/freetype" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX_ALIAS" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    "-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG -g0 -ffile-prefix-map=$FREETYPE_SOURCE_ALIAS=/usr/src/secunda/freetype" \
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

if [[ ! -f "$NETTLE_ARCHIVE" ]]; then
    curl --fail --location --retry 3 \
        --output "$NETTLE_ARCHIVE" \
        "https://ftp.gnu.org/gnu/nettle/nettle-$NETTLE_VERSION.tar.gz"
fi
actual_nettle_sha256=$(shasum -a 256 "$NETTLE_ARCHIVE" | awk '{print $1}')
if [[ "$actual_nettle_sha256" != "$NETTLE_SHA256" ]]; then
    echo "Nettle source checksum mismatch." >&2
    echo "Expected: $NETTLE_SHA256" >&2
    echo "Actual:   $actual_nettle_sha256" >&2
    exit 1
fi
if [[ ! -f "$NETTLE_SOURCE/Makefile.in" ]]; then
    mkdir -p "$NETTLE_SOURCE"
    tar -xzf "$NETTLE_ARCHIVE" --strip-components=1 -C "$NETTLE_SOURCE"
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

"$SCRIPT_DIR/verify-runtime-dependencies.sh" "$PREFIX" "$DEPLOYMENT_TARGET" --write-stamp

echo "Secunda x86_64 runtime dependencies staged at $PREFIX"
