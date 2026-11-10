#!/bin/zsh
# Fetch Sparkle's release tools (generate_keys, sign_update) into
# build/sparkle-tools. The archive is pinned by version and SHA-256 and must
# match the Sparkle version in Package.swift.
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
SPARKLE_VERSION=2.10.1
EXPECTED_SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
TOOLS_ROOT="$REPOSITORY_ROOT/build/sparkle-tools/$SPARKLE_VERSION"

if [[ -x "$TOOLS_ROOT/bin/sign_update" && -x "$TOOLS_ROOT/bin/generate_keys" ]]; then
    print -r -- "$TOOLS_ROOT/bin"
    exit 0
fi

DOWNLOAD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-sparkle.XXXXXX")
trap 'rm -rf "$DOWNLOAD_ROOT"' EXIT
ARCHIVE="$DOWNLOAD_ROOT/Sparkle-$SPARKLE_VERSION.tar.xz"
/usr/bin/curl --fail --location --silent --show-error --proto '=https' \
    --output "$ARCHIVE" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
actual=$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')
if [[ "$actual" != "$EXPECTED_SHA256" ]]; then
    echo "Sparkle tools archive checksum mismatch: $actual" >&2
    exit 1
fi
mkdir -p "$DOWNLOAD_ROOT/extract"
/usr/bin/tar -xf "$ARCHIVE" -C "$DOWNLOAD_ROOT/extract"
rm -rf "$TOOLS_ROOT"
mkdir -p "$TOOLS_ROOT"
ditto "$DOWNLOAD_ROOT/extract/bin" "$TOOLS_ROOT/bin"
ditto "$DOWNLOAD_ROOT/extract/LICENSE" "$TOOLS_ROOT/LICENSE"
print -r -- "$TOOLS_ROOT/bin"
