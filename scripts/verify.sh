#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}

cd "$REPOSITORY_ROOT"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/secunda-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/secunda-swiftpm-cache"
swift run \
    --disable-sandbox \
    --triple arm64-apple-macosx15.0 \
    SecundaLauncher \
    --self-test

"$REPOSITORY_ROOT/scripts/test-source-only-provenance.sh"
