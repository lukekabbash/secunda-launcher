#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
RUNTIME_ROOT=${1:-"$REPOSITORY_ROOT/Runtime/wine"}
VERSION="0.80"
EXPECTED_SHA256="8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"
DOWNLOAD_URL="https://github.com/3Shain/dxmt/releases/download/v${VERSION}/dxmt-v${VERSION}-builtin.tar.gz"
STAGE_ROOT=$(mktemp -d /private/tmp/secunda-dxmt.XXXXXX)
ARCHIVE="$STAGE_ROOT/dxmt.tar.gz"
PREVERIFIED_SOURCE=${SECUNDA_DXMT_SOURCE:-}

if [[ ! -d "$RUNTIME_ROOT/lib/wine" ]]; then
    echo "Runtime library directory not found: $RUNTIME_ROOT/lib/wine" >&2
    exit 1
fi

if [[ -n "$PREVERIFIED_SOURCE" ]]; then
    if [[ ! -d "$PREVERIFIED_SOURCE" ]]; then
        echo "Preverified DXMT source not found: $PREVERIFIED_SOURCE" >&2
        exit 1
    fi
    ditto "$PREVERIFIED_SOURCE" "$STAGE_ROOT/v${VERSION}"
else
    curl -fL "$DOWNLOAD_URL" -o "$ARCHIVE"
    ACTUAL_SHA256=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
    if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
        echo "DXMT checksum mismatch." >&2
        echo "Expected: $EXPECTED_SHA256" >&2
        echo "Actual:   $ACTUAL_SHA256" >&2
        exit 1
    fi
    tar -xzf "$ARCHIVE" -C "$STAGE_ROOT"
fi
ditto "$STAGE_ROOT/v${VERSION}" "$RUNTIME_ROOT/lib/wine"
codesign --force --sign - "$RUNTIME_ROOT/lib/wine/x86_64-unix/winemetal.so"

for required_file in \
    "$RUNTIME_ROOT/lib/wine/x86_64-unix/winemetal.so" \
    "$RUNTIME_ROOT/lib/wine/x86_64-windows/d3d11.dll" \
    "$RUNTIME_ROOT/lib/wine/x86_64-windows/dxgi.dll"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Missing graphics runtime file: $required_file" >&2
        exit 1
    fi
done

echo "$VERSION" > "$RUNTIME_ROOT/lib/wine/.secunda-dxmt-version"

echo "DXMT v${VERSION} verified and staged in $RUNTIME_ROOT"
echo "Temporary download: $STAGE_ROOT"
