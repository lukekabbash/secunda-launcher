#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
RUNTIME_ROOT=${1:-"$REPOSITORY_ROOT/Runtime/wine"}
RUNTIME_ROOT=${RUNTIME_ROOT:A}
INTEGRITY_RELATIVE='share/secunda/runtime-files.sha256'
INTEGRITY_PATH="$RUNTIME_ROOT/$INTEGRITY_RELATIVE"
LINKS_RELATIVE='share/secunda/runtime-links.tsv'
LINKS_PATH="$RUNTIME_ROOT/$LINKS_RELATIVE"
MODES_RELATIVE='share/secunda/runtime-modes.tsv'
MODES_PATH="$RUNTIME_ROOT/$MODES_RELATIVE"
TEMP_MANIFEST=$(mktemp "${TMPDIR:-/tmp}/secunda-runtime-integrity.XXXXXX")
TEMP_LINKS=$(mktemp "${TMPDIR:-/tmp}/secunda-runtime-links.XXXXXX")
TEMP_MODES=$(mktemp "${TMPDIR:-/tmp}/secunda-runtime-modes.XXXXXX")

cleanup() {
    rm -f "$TEMP_MANIFEST" "$TEMP_LINKS" "$TEMP_MODES"
}
trap cleanup EXIT

if [[ ! -d "$RUNTIME_ROOT" || ! -x "$RUNTIME_ROOT/bin/wine" ]]; then
    echo "Incomplete Secunda runtime: $RUNTIME_ROOT" >&2
    exit 1
fi

mkdir -p "${INTEGRITY_PATH:h}"
# Materialize both metadata files before scanning so their own modes are part of
# the exact handoff contract. The checksum file is intentionally content-exempt
# because it cannot hash itself.
install -m 0644 "$TEMP_MANIFEST" "$INTEGRITY_PATH"
install -m 0644 "$TEMP_MODES" "$MODES_PATH"
(
    cd "$RUNTIME_ROOT"
    find . -type l -print0 | LC_ALL=C sort -z |
        while IFS= read -r -d '' runtime_link; do
            link_target=$(readlink "$runtime_link")
            if [[ "$runtime_link" == *$'\n'* || "$runtime_link" == *$'\t'* || \
                "$link_target" == *$'\n'* || "$link_target" == *$'\t'* ]]; then
                echo "Runtime symlink inventory contains an unsupported path character." >&2
                exit 1
            fi
            printf '%s\t%s\n' "$runtime_link" "$link_target"
        done
) > "$TEMP_LINKS"
install -m 0644 "$TEMP_LINKS" "$LINKS_PATH"

(
    cd "$RUNTIME_ROOT"
    find . \( -type d -o -type f \) -print0 | LC_ALL=C sort -z |
        while IFS= read -r -d '' runtime_entry; do
            if [[ "$runtime_entry" == *$'\n'* || "$runtime_entry" == *$'\t'* ]]; then
                echo "Runtime mode inventory contains an unsupported path character." >&2
                exit 1
            fi
            entry_mode=$(/usr/bin/stat -f '%Lp' "$runtime_entry")
            printf '%s\t%s\n' "$runtime_entry" "$entry_mode"
        done
) > "$TEMP_MODES"
install -m 0644 "$TEMP_MODES" "$MODES_PATH"

(
    cd "$RUNTIME_ROOT"
    find . -type f ! -path "./$INTEGRITY_RELATIVE" -print0 | LC_ALL=C sort -z |
        xargs -0 shasum -a 256
) > "$TEMP_MANIFEST"

install -m 0644 "$TEMP_MANIFEST" "$INTEGRITY_PATH"
"$SCRIPT_DIR/verify-runtime-integrity.sh" "$RUNTIME_ROOT" >/dev/null

file_count=$(wc -l < "$INTEGRITY_PATH" | tr -d ' ')
link_count=$(wc -l < "$LINKS_PATH" | tr -d ' ')
mode_count=$(wc -l < "$MODES_PATH" | tr -d ' ')
echo "Created and verified $file_count file checksums, $link_count symlink targets, and $mode_count modes."
