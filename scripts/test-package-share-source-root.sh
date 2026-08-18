#!/bin/zsh
set -euo pipefail

# macos-15 share-DMG packaging failed in stage-runtime-notices.sh:
#   Required license file is missing: .../sources/wine/LICENSE
# The Wine compile extracts sources into a temp directory and deletes it.
# A restored Runtime/wine-macos15 cache does not bring sources/ back.

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-source-root-test.XXXXXX")
pass_count=0

cleanup() {
    rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
    print -u2 -- "FAIL: $1"
    exit 1
}

pass() {
    pass_count=$((pass_count + 1))
    print -- "PASS: $1"
}

if [[ ! -x "$SCRIPT_DIR/prepare-source-root.sh" ]]; then
    fail "prepare-source-root.sh must be executable"
fi
pass "prepare-source-root.sh is executable"

if grep -Fq 'prepare-source-root.sh' "$SCRIPT_DIR/package-share-dmg.sh" && \
    grep -Fq 'SECUNDA_SOURCE_ROOT' "$SCRIPT_DIR/package-share-dmg.sh"; then
    pass "package-share-dmg.sh prepares SECUNDA_SOURCE_ROOT from the archive"
else
    fail "package-share-dmg.sh does not prepare SECUNDA_SOURCE_ROOT from the archive"
fi

if grep -Fq 'prepare-source-root.sh' "$REPOSITORY_ROOT/.github/workflows/package-share-dmg.yml"; then
    pass "share-DMG workflow extracts sources before packaging"
else
    fail "share-DMG workflow does not extract sources before packaging"
fi

if grep -Fq 'path: Runtime/wine-macos15' "$REPOSITORY_ROOT/.github/workflows/package-share-dmg.yml" && \
    ! grep -E 'hashFiles\([^)]*package-share-dmg\.sh' \
        "$REPOSITORY_ROOT/.github/workflows/package-share-dmg.yml" >/dev/null && \
    ! grep -E 'hashFiles\([^)]*prepare-source-root\.sh' \
        "$REPOSITORY_ROOT/.github/workflows/package-share-dmg.yml" >/dev/null; then
    pass "runtime cache key still ignores packaging-only notice extract scripts"
else
    fail "runtime cache key must not include packaging-only notice extract scripts"
fi

ARCHIVE_ROOT="$TEST_ROOT/archive-tree"
mkdir -p "$ARCHIVE_ROOT/sources/wine"
print -r -- 'Wine license fixture' > "$ARCHIVE_ROOT/sources/wine/LICENSE"
ARCHIVE="$TEST_ROOT/crossover-sources-fixture.tar.gz"
tar -czf "$ARCHIVE" -C "$ARCHIVE_ROOT" sources

if "$SCRIPT_DIR/prepare-source-root.sh" >/dev/null 2>"$TEST_ROOT/usage.err"; then
    fail "prepare-source-root.sh should require archive and destination"
else
    pass "prepare-source-root.sh rejects a missing archive argument"
fi

DEST="$TEST_ROOT/extract"
SOURCE_ROOT=$("$SCRIPT_DIR/prepare-source-root.sh" "$ARCHIVE" "$DEST")
if [[ "$SOURCE_ROOT" == "$DEST/sources" && -f "$SOURCE_ROOT/wine/LICENSE" ]]; then
    pass "prepare-source-root.sh extracts sources/wine/LICENSE from the archive"
else
    fail "prepare-source-root.sh did not produce $DEST/sources/wine/LICENSE"
fi

EMPTY_ARCHIVE="$TEST_ROOT/empty.tar.gz"
mkdir -p "$TEST_ROOT/empty-tree"
tar -czf "$EMPTY_ARCHIVE" -C "$TEST_ROOT/empty-tree" .
if "$SCRIPT_DIR/prepare-source-root.sh" "$EMPTY_ARCHIVE" "$TEST_ROOT/empty-extract" \
    >/dev/null 2>"$TEST_ROOT/empty.err"; then
    fail "prepare-source-root.sh should reject an archive without wine/LICENSE"
else
    grep -Fq 'sources/wine/LICENSE' "$TEST_ROOT/empty.err" || \
        fail "missing-license error should name sources/wine/LICENSE"
    pass "prepare-source-root.sh rejects an archive without wine/LICENSE"
fi

FAKE_RUNTIME="$TEST_ROOT/runtime"
FAKE_SOURCES="$TEST_ROOT/notice-sources"
mkdir -p "$FAKE_RUNTIME/bin" \
    "$FAKE_SOURCES/wine/libs/capstone" \
    "$FAKE_SOURCES/wine/libs/compiler-rt" \
    "$FAKE_SOURCES/wine/libs/faudio" \
    "$FAKE_SOURCES/wine/libs/fluidsynth" \
    "$FAKE_SOURCES/wine/libs/gsm" \
    "$FAKE_SOURCES/wine/libs/jpeg" \
    "$FAKE_SOURCES/wine/libs/jxr" \
    "$FAKE_SOURCES/wine/libs/lcms2" \
    "$FAKE_SOURCES/wine/libs/ldap" \
    "$FAKE_SOURCES/wine/libs/mpg123" \
    "$FAKE_SOURCES/wine/libs/musl" \
    "$FAKE_SOURCES/wine/libs/png" \
    "$FAKE_SOURCES/wine/libs/tiff" \
    "$FAKE_SOURCES/wine/libs/tomcrypt" \
    "$FAKE_SOURCES/wine/libs/vkd3d" \
    "$FAKE_SOURCES/wine/libs/xml2" \
    "$FAKE_SOURCES/wine/libs/xslt" \
    "$FAKE_SOURCES/wine/libs/zlib" \
    "$FAKE_SOURCES/freetype/docs" \
    "$FAKE_SOURCES/gnutls/gmp" \
    "$FAKE_SOURCES/gnutls/nettle" \
    "$FAKE_SOURCES/gnutls/gnutls/doc"
print '#!/bin/zsh\nexit 0' > "$FAKE_RUNTIME/bin/wine"
chmod +x "$FAKE_RUNTIME/bin/wine"
for notice_file in \
    "$FAKE_SOURCES/wine/LICENSE" \
    "$FAKE_SOURCES/wine/AUTHORS" \
    "$FAKE_SOURCES/wine/COPYING.LIB" \
    "$FAKE_SOURCES/freetype/docs/FTL.TXT" \
    "$FAKE_SOURCES/gnutls/gmp/COPYING.LESSERv3" \
    "$FAKE_SOURCES/gnutls/gmp/COPYINGv3" \
    "$FAKE_SOURCES/gnutls/gmp/COPYINGv2" \
    "$FAKE_SOURCES/gnutls/nettle/COPYING.LESSERv3" \
    "$FAKE_SOURCES/gnutls/nettle/COPYINGv3" \
    "$FAKE_SOURCES/gnutls/gnutls/LICENSE" \
    "$FAKE_SOURCES/gnutls/gnutls/doc/COPYING.LESSER" \
    "$FAKE_SOURCES/wine/libs/capstone/LICENSE.TXT" \
    "$FAKE_SOURCES/wine/libs/capstone/LICENSE_LLVM.TXT" \
    "$FAKE_SOURCES/wine/libs/compiler-rt/LICENSE.TXT" \
    "$FAKE_SOURCES/wine/libs/faudio/LICENSE" \
    "$FAKE_SOURCES/wine/libs/fluidsynth/COPYING.md" \
    "$FAKE_SOURCES/wine/libs/gsm/COPYRIGHT" \
    "$FAKE_SOURCES/wine/libs/jpeg/LICENSE" \
    "$FAKE_SOURCES/wine/libs/jxr/LICENSE" \
    "$FAKE_SOURCES/wine/libs/lcms2/COPYING" \
    "$FAKE_SOURCES/wine/libs/ldap/LICENSE" \
    "$FAKE_SOURCES/wine/libs/ldap/COPYRIGHT" \
    "$FAKE_SOURCES/wine/libs/mpg123/LICENSE" \
    "$FAKE_SOURCES/wine/libs/musl/COPYRIGHT" \
    "$FAKE_SOURCES/wine/libs/png/LICENSE" \
    "$FAKE_SOURCES/wine/libs/tiff/COPYRIGHT" \
    "$FAKE_SOURCES/wine/libs/tomcrypt/LICENSE" \
    "$FAKE_SOURCES/wine/libs/vkd3d/COPYING" \
    "$FAKE_SOURCES/wine/libs/xml2/COPYING" \
    "$FAKE_SOURCES/wine/libs/xslt/COPYING" \
    "$FAKE_SOURCES/wine/libs/zlib/LICENSE"; do
    print -r -- "fixture" > "$notice_file"
done

if SECUNDA_SOURCE_ROOT="$FAKE_SOURCES" \
    "$SCRIPT_DIR/stage-runtime-notices.sh" "$FAKE_RUNTIME" \
    >"$TEST_ROOT/notices.out" 2>"$TEST_ROOT/notices.err"; then
    if [[ -f "$FAKE_RUNTIME/share/secunda/licenses/Wine-NOTICE.txt" ]]; then
        pass "stage-runtime-notices.sh reads licenses from SECUNDA_SOURCE_ROOT"
    else
        fail "stage-runtime-notices.sh did not stage Wine-NOTICE.txt"
    fi
else
    cat "$TEST_ROOT/notices.err" >&2
    fail "stage-runtime-notices.sh should succeed when SECUNDA_SOURCE_ROOT is set"
fi

MISSING_RUNTIME="$TEST_ROOT/missing-sources-runtime"
mkdir -p "$MISSING_RUNTIME/bin"
print '#!/bin/zsh\nexit 0' > "$MISSING_RUNTIME/bin/wine"
chmod +x "$MISSING_RUNTIME/bin/wine"
if SECUNDA_SOURCE_ROOT="$TEST_ROOT/does-not-exist" \
    "$SCRIPT_DIR/stage-runtime-notices.sh" "$MISSING_RUNTIME" \
    >/dev/null 2>"$TEST_ROOT/missing.err"; then
    fail "stage-runtime-notices.sh should fail without wine/LICENSE"
else
    grep -Fq 'wine/LICENSE' "$TEST_ROOT/missing.err" || \
        fail "missing-source failure should name wine/LICENSE"
    pass "stage-runtime-notices.sh fails closed when wine/LICENSE is absent"
fi

print -- "PASS: $pass_count package-share source-root checks"
