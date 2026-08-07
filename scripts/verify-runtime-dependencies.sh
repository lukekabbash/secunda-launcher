#!/bin/zsh
set -euo pipefail

PREFIX_ROOT=${1:-}
[[ -n "$PREFIX_ROOT" ]] && PREFIX_ROOT=${PREFIX_ROOT:A}
DEPLOYMENT_TARGET=${2:-15.0}
MODE=${3:---verify}
STAMP_RELATIVE='share/secunda/dependencies.complete'
STAMP_PATH="$PREFIX_ROOT/$STAMP_RELATIVE"
TEMP_STAMP=$(mktemp "${TMPDIR:-/tmp}/secunda-dependencies.XXXXXX")
DEPENDENCY_FILES=(
    lib/libfreetype.6.dylib
    lib/libgmp.10.dylib
    lib/libnettle.8.dylib
    lib/libhogweed.6.dylib
    lib/libgnutls.30.dylib
)

cleanup() {
    rm -f "$TEMP_STAMP"
}
trap cleanup EXIT

if [[ -z "$PREFIX_ROOT" || ! -d "$PREFIX_ROOT" ]]; then
    echo "Usage: $0 dependency-prefix [deployment-target] [--verify|--write-stamp]" >&2
    exit 64
fi
case "$MODE" in
    --verify|--write-stamp) ;;
    *)
        echo "Unknown dependency verification mode: $MODE" >&2
        exit 64
        ;;
esac

is_newer_version() {
    awk -v actual="$1" -v maximum="$2" 'BEGIN {
        split(actual, a, "."); split(maximum, m, ".");
        if ((a[1] + 0) > (m[1] + 0)) exit 0;
        if ((a[1] + 0) < (m[1] + 0)) exit 1;
        exit ((a[2] + 0) > (m[2] + 0)) ? 0 : 1;
    }'
}

for relative_file in "${DEPENDENCY_FILES[@]}"; do
    dependency_file="$PREFIX_ROOT/$relative_file"
    if [[ ! -f "$dependency_file" ]]; then
        echo "Dependency prefix is incomplete: $dependency_file" >&2
        exit 1
    fi
    file_description=$(file -b "$dependency_file")
    if [[ "$file_description" != *Mach-O* || "$file_description" != *x86_64* ]]; then
        echo "Dependency is not x86_64 Mach-O code: $dependency_file" >&2
        exit 1
    fi
    minimum_os=$(vtool -show-build "$dependency_file" 2>/dev/null | awk '/minos/{print $2; exit}')
    if [[ -z "$minimum_os" ]] || is_newer_version "$minimum_os" "$DEPLOYMENT_TARGET"; then
        echo "Dependency exceeds the macOS $DEPLOYMENT_TARGET floor: $dependency_file (${minimum_os:-unknown})" >&2
        exit 1
    fi
done

{
    printf 'deployment_target=%s\n' "$DEPLOYMENT_TARGET"
    (
        cd "$PREFIX_ROOT"
        shasum -a 256 "${DEPENDENCY_FILES[@]}"
    )
} > "$TEMP_STAMP"

if [[ "$MODE" == "--write-stamp" ]]; then
    mkdir -p "${STAMP_PATH:h}"
    install -m 0644 "$TEMP_STAMP" "$STAMP_PATH"
    echo "PASS: dependency completion stamp written for macOS $DEPLOYMENT_TARGET."
elif [[ ! -f "$STAMP_PATH" ]] || ! cmp -s "$STAMP_PATH" "$TEMP_STAMP"; then
    echo "Dependency completion stamp is missing or stale: $STAMP_PATH" >&2
    exit 1
else
    echo "PASS: five pinned x86_64 dependencies match their macOS $DEPLOYMENT_TARGET completion stamp."
fi
