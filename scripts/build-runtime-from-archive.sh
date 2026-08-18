#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
SOURCE_ARCHIVE=${1:-${SECUNDA_SOURCE_ARCHIVE:-"$REPOSITORY_ROOT/crossover-sources-26.3.0.tar.gz"}}
RUNTIME_OUTPUT=${2:-${SECUNDA_RUNTIME_OUTPUT:-"$REPOSITORY_ROOT/Runtime/wine-macos15"}}
# GitHub-hosted macOS runners set TMPDIR with a trailing slash (`.../T/`).
# Joining that with a relative name produces `T//secunda-clean-runtime.*`.
# The linker stores the collapsed `T/` form, so an exact install_name_tool
# -change against the uncollapsed alias is a silent no-op.
BUILD_TMPDIR=${TMPDIR:-/private/tmp}
BUILD_TMPDIR=${BUILD_TMPDIR%/}
BUILD_CONTAINER=$(mktemp -d "$BUILD_TMPDIR/secunda-clean-runtime.XXXXXX")
SOURCE_EXTRACT_ROOT="$BUILD_CONTAINER/source"
ALIAS_ROOT="$BUILD_CONTAINER/aliases"
BUILD_USER=$(id -un)
BUILD_USER_HOME=${HOME:?}

cleanup() {
    rm -rf "$BUILD_CONTAINER"
}
trap cleanup EXIT

if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    echo "Verified source archive not found: $SOURCE_ARCHIVE" >&2
    exit 1
fi
if [[ -e "$RUNTIME_OUTPUT" || -L "$RUNTIME_OUTPUT" ]]; then
    echo "Refusing to overwrite an existing runtime: $RUNTIME_OUTPUT" >&2
    exit 1
fi

"$SCRIPT_DIR/verify-build-provenance.sh" "$SOURCE_ARCHIVE"
mkdir -p "$SOURCE_EXTRACT_ROOT" "$ALIAS_ROOT"
tar -xzf "$SOURCE_ARCHIVE" -C "$SOURCE_EXTRACT_ROOT"

SOURCE_ROOT="$SOURCE_EXTRACT_ROOT/sources"
for required_source in \
    "$SOURCE_ROOT/wine/configure" \
    "$SOURCE_ROOT/freetype/CMakeLists.txt" \
    "$SOURCE_ROOT/gnutls/gmp/configure" \
    "$SOURCE_ROOT/gnutls/gnutls/configure"; do
    if [[ ! -f "$required_source" ]]; then
        echo "Verified archive is missing a build source: $required_source" >&2
        exit 1
    fi
done

env -i \
    HOME="$BUILD_USER_HOME" \
    USER="$BUILD_USER" \
    LOGNAME="$BUILD_USER" \
    LANG=en_US.UTF-8 \
    LC_CTYPE=UTF-8 \
    PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="$BUILD_TMPDIR" \
    SECUNDA_DEPLOYMENT_TARGET=15.0 \
    SECUNDA_SOURCE_ROOT="$SOURCE_ROOT" \
    SECUNDA_SOURCE_CACHE_ROOT="$REPOSITORY_ROOT/build/source-cache" \
    SECUNDA_DEPENDENCY_BUILD_ROOT="$BUILD_CONTAINER/dependencies" \
    SECUNDA_DEPENDENCY_BUILD_ROOT_ALIAS="$ALIAS_ROOT/dependency-build" \
    SECUNDA_DEPENDENCY_PREFIX="$BUILD_CONTAINER/dependencies/prefix" \
    SECUNDA_DEPENDENCY_PREFIX_ALIAS="$ALIAS_ROOT/dependency-prefix" \
    SECUNDA_FREETYPE_SOURCE_ALIAS="$ALIAS_ROOT/freetype-source" \
    SECUNDA_GMP_SOURCE_ALIAS="$ALIAS_ROOT/gmp-source" \
    SECUNDA_GNUTLS_SOURCE_ALIAS="$ALIAS_ROOT/gnutls-source" \
    SECUNDA_NETTLE_SOURCE_ALIAS="$ALIAS_ROOT/nettle-source" \
    SECUNDA_WINE_BUILD_ROOT="$BUILD_CONTAINER/wine-build" \
    SECUNDA_WINE_BUILD_ROOT_ALIAS="$ALIAS_ROOT/wine-build" \
    SECUNDA_WINE_SOURCE_ALIAS="$ALIAS_ROOT/wine-source" \
    SECUNDA_RUNTIME_OUTPUT="$RUNTIME_OUTPUT" \
    "$SCRIPT_DIR/build-runtime.sh"

echo "PASS: runtime built from a fresh verified archive extraction: $RUNTIME_OUTPUT"
