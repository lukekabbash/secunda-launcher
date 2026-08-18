#!/bin/zsh
set -euo pipefail

# Extract the corresponding CrossOver source tree so stage-runtime-notices.sh
# can read Wine, FreeType, and GnuTLS license files.
#
# GitHub-hosted macos-15 never leaves repository sources/ on disk:
# build-runtime-from-archive.sh extracts into a temp directory and deletes it,
# and a restored Runtime/wine-macos15 cache does not include sources/.
#
# Usage: prepare-source-root.sh ARCHIVE DEST
# Prints DEST/sources on stdout.

SOURCE_ARCHIVE=${1:-}
DEST=${2:-}

if [[ -z "$SOURCE_ARCHIVE" || -z "$DEST" ]]; then
    echo "Usage: $0 path-to-crossover-sources.tar.gz destination-directory" >&2
    exit 64
fi
if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    echo "Source archive not found: $SOURCE_ARCHIVE" >&2
    exit 1
fi

mkdir -p "$DEST"
tar -xzf "$SOURCE_ARCHIVE" -C "$DEST"
if [[ ! -f "$DEST/sources/wine/LICENSE" ]]; then
    echo "Source archive is missing sources/wine/LICENSE after extraction." >&2
    exit 1
fi
print -r -- "$DEST/sources"
