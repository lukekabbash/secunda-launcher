#!/bin/zsh
set -euo pipefail

# Contracts for relocating Autotools LC_LOAD_DYLIB strings. The macos-15
# share-DMG job failed when install_name_tool -change used a guessed
# SECUNDA_DEPENDENCY_PREFIX_ALIAS that did not match the collapsed path
# the linker stored.

pass_count=0

fail() {
    print -u2 -- "FAIL: $1"
    exit 1
}

pass() {
    pass_count=$((pass_count + 1))
    print -- "PASS: $1"
}

collapse_tmpdir() {
    local tmpdir=${1:-/private/tmp}
    print -r -- "${tmpdir%/}"
}

is_system_or_relocated_dependency() {
    case "$1" in
        @*|/usr/lib/*|/System/Library/*|/Library/Apple/*) return 0 ;;
        *) return 1 ;;
    esac
}

relocated_install_name() {
    print -r -- "@rpath/${1:t}"
}

if [[ "$(collapse_tmpdir '/var/folders/_5/zjnzxgh147qcg3bb5cg2wvqw0000gn/T/')" == \
        '/var/folders/_5/zjnzxgh147qcg3bb5cg2wvqw0000gn/T' ]]; then
    pass "GitHub runner TMPDIR trailing slash collapses to a single T/"
else
    fail "GitHub runner TMPDIR trailing slash collapses to a single T/"
fi

if [[ "$(collapse_tmpdir '/private/tmp')" == '/private/tmp' ]]; then
    pass "default TMPDIR stays /private/tmp"
else
    fail "default TMPDIR stays /private/tmp"
fi

tmpdir=$(collapse_tmpdir '/var/folders/_5/zjnzxgh147qcg3bb5cg2wvqw0000gn/T/')
container="$tmpdir/secunda-clean-runtime.6XAoKj"
alias_prefix="$container/aliases/dependency-prefix"
if [[ "$alias_prefix" != *//* ]]; then
    pass "collapsed TMPDIR join does not introduce T//"
else
    fail "collapsed TMPDIR join does not introduce T//"
fi

# Exact strings from actions/runs/32152138518
uncollapsed_alias='/var/folders/_5/zjnzxgh147qcg3bb5cg2wvqw0000gn/T//secunda-clean-runtime.6XAoKj/aliases/dependency-prefix'
stored='/var/folders/_5/zjnzxgh147qcg3bb5cg2wvqw0000gn/T/secunda-clean-runtime.6XAoKj/aliases/dependency-prefix/lib/libhogweed.6.dylib'
if [[ "$uncollapsed_alias/lib/libhogweed.6.dylib" != "$stored" ]]; then
    pass "uncollapsed alias plus lib name is not the linker-stored load command"
else
    fail "uncollapsed alias plus lib name is not the linker-stored load command"
fi
if [[ "$(relocated_install_name "$stored")" == '@rpath/libhogweed.6.dylib' ]]; then
    pass "rewrite uses the otool basename, not a guessed prefix"
else
    fail "rewrite uses the otool basename, not a guessed prefix"
fi

for dependency in \
    '/var/folders/_5/zjnzxgh147qcg3bb5cg2wvqw0000gn/T/secunda-clean-runtime.6XAoKj/aliases/dependency-prefix/lib/libhogweed.6.dylib' \
    '/var/folders/_5/zjnzxgh147qcg3bb5cg2wvqw0000gn/T/secunda-clean-runtime.6XAoKj/aliases/dependency-prefix/lib/libnettle.8.dylib' \
    '/var/folders/_5/zjnzxgh147qcg3bb5cg2wvqw0000gn/T/secunda-clean-runtime.6XAoKj/aliases/dependency-prefix/lib/libgmp.10.dylib' \
    '/private/tmp/secunda-dependency-prefix-x86_64-macos15_0/lib/libgnutls.30.dylib'
do
    if is_system_or_relocated_dependency "$dependency"; then
        fail "absolute prefix must be rewritten: $dependency"
    else
        pass "absolute prefix must be rewritten: $dependency"
    fi
done

for dependency in \
    '@rpath/libhogweed.6.dylib' \
    '@loader_path/libgmp.10.dylib' \
    '/usr/lib/libSystem.B.dylib' \
    '/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation' \
    '/Library/Apple/System/Library/PrivateFrameworks/SiriTTS.framework/SiriTTS'
do
    if is_system_or_relocated_dependency "$dependency"; then
        pass "distributable dependency is left alone: $dependency"
    else
        fail "distributable dependency is left alone: $dependency"
    fi
done

print -- "PASS: $pass_count relocate-runtime contracts"
