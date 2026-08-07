#!/bin/zsh
set -euo pipefail

STAGED_ROOT=${1:-}
DESTINATION_ROOT=${2:-}
LOCK_HELD=0

if [[ -z "$STAGED_ROOT" || -z "$DESTINATION_ROOT" ]]; then
    echo "Usage: $0 staged-runtime destination-runtime" >&2
    exit 64
fi

STAGED_ROOT=${STAGED_ROOT:A}
DESTINATION_ROOT=${DESTINATION_ROOT:A}
PUBLISH_LOCK="${DESTINATION_ROOT}.publish.lock"

cleanup() {
    if (( ${LOCK_HELD:-0} == 1 )); then
        rmdir "$PUBLISH_LOCK" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if [[ ! -d "$STAGED_ROOT" || -L "$STAGED_ROOT" ]]; then
    echo "Runtime publication stage is not a real directory: $STAGED_ROOT" >&2
    exit 1
fi
if [[ "${STAGED_ROOT:h}" != "${DESTINATION_ROOT:h}" ]]; then
    echo "Runtime stage and destination must share a parent for atomic publication." >&2
    exit 1
fi
if [[ -e "$DESTINATION_ROOT" || -L "$DESTINATION_ROOT" ]]; then
    echo "Refusing to overwrite an existing runtime: $DESTINATION_ROOT" >&2
    exit 1
fi
if ! mkdir "$PUBLISH_LOCK" 2>/dev/null; then
    echo "Another runtime publisher holds the output lock: $PUBLISH_LOCK" >&2
    exit 1
fi
LOCK_HELD=1
if [[ -e "$DESTINATION_ROOT" || -L "$DESTINATION_ROOT" ]]; then
    echo "Runtime destination appeared while acquiring the publication lock: $DESTINATION_ROOT" >&2
    exit 1
fi

mv "$STAGED_ROOT" "$DESTINATION_ROOT"
if ! rmdir "$PUBLISH_LOCK"; then
    echo "Runtime published, but its output lock could not be released: $PUBLISH_LOCK" >&2
    exit 1
fi
LOCK_HELD=0

echo "PASS: verified runtime published without replacing an existing destination."
