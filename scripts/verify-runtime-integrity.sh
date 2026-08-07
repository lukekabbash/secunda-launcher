#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
RUNTIME_ROOT=${1:-"$REPOSITORY_ROOT/Runtime/wine"}
RUNTIME_ROOT=${RUNTIME_ROOT:A}
INTEGRITY_RELATIVE='share/secunda/runtime-files.sha256'
LINKS_RELATIVE='share/secunda/runtime-links.tsv'
INTEGRITY_PATH="$RUNTIME_ROOT/$INTEGRITY_RELATIVE"
LINKS_PATH="$RUNTIME_ROOT/$LINKS_RELATIVE"
MODES_RELATIVE='share/secunda/runtime-modes.tsv'
MODES_PATH="$RUNTIME_ROOT/$MODES_RELATIVE"
EXPECTED_FILES=$(mktemp "${TMPDIR:-/tmp}/secunda-runtime-files-verify.XXXXXX")
EXPECTED_LINKS=$(mktemp "${TMPDIR:-/tmp}/secunda-runtime-links-verify.XXXXXX")
EXPECTED_MODES=$(mktemp "${TMPDIR:-/tmp}/secunda-runtime-modes-verify.XXXXXX")

cleanup() {
    rm -f "$EXPECTED_FILES" "$EXPECTED_LINKS" "$EXPECTED_MODES"
}
trap cleanup EXIT

if [[ ! -f "$INTEGRITY_PATH" || ! -f "$LINKS_PATH" || ! -f "$MODES_PATH" ]]; then
    echo "Runtime integrity inventories are missing under $RUNTIME_ROOT." >&2
    exit 1
fi

for required_worker in \
    "$RUNTIME_ROOT/bin/wine" \
    "$RUNTIME_ROOT/bin/wineserver" \
    "$RUNTIME_ROOT/lib/wine/x86_64-unix/wine"; do
    if [[ ! -x "$required_worker" ]]; then
        echo "Runtime worker is not executable: $required_worker" >&2
        exit 1
    fi
    worker_mode=$(/usr/bin/stat -f '%Lp' "$required_worker")
    if (( (8#$worker_mode & 8#555) != 8#555 )); then
        echo "Runtime worker is not readable and executable after handoff: $required_worker ($worker_mode)" >&2
        exit 1
    fi
done

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
            if [[ ! -e "$runtime_link" ]]; then
                echo "Runtime contains a dangling symlink: $runtime_link -> $link_target" >&2
                exit 1
            fi
            resolved_link=${runtime_link:A}
            if [[ "$resolved_link" != "$RUNTIME_ROOT"/* ]]; then
                echo "Runtime symlink escapes the bundle: $runtime_link -> $link_target" >&2
                exit 1
            fi
            printf '%s\t%s\n' "$runtime_link" "$link_target"
        done
) > "$EXPECTED_LINKS"

if ! cmp -s "$LINKS_PATH" "$EXPECTED_LINKS"; then
    echo "Runtime symlink inventory does not match $LINKS_RELATIVE." >&2
    exit 1
fi

(
    cd "$RUNTIME_ROOT"
    find . \( -type d -o -type f \) -print0 | LC_ALL=C sort -z |
        while IFS= read -r -d '' runtime_entry; do
            if [[ "$runtime_entry" == *$'\n'* || "$runtime_entry" == *$'\t'* ]]; then
                echo "Runtime mode inventory contains an unsupported path character." >&2
                exit 1
            fi
            entry_mode=$(/usr/bin/stat -f '%Lp' "$runtime_entry")
            if [[ -d "$runtime_entry" ]] && (( (8#$entry_mode & 8#555) != 8#555 )); then
                echo "Runtime directory is not readable and traversable: $runtime_entry ($entry_mode)" >&2
                exit 1
            fi
            if [[ -f "$runtime_entry" ]] && (( (8#$entry_mode & 8#444) != 8#444 )); then
                echo "Runtime file is not readable after handoff: $runtime_entry ($entry_mode)" >&2
                exit 1
            fi
            printf '%s\t%s\n' "$runtime_entry" "$entry_mode"
        done
) > "$EXPECTED_MODES"

if ! cmp -s "$MODES_PATH" "$EXPECTED_MODES"; then
    echo "Runtime mode inventory does not match $MODES_RELATIVE." >&2
    exit 1
fi

(
    cd "$RUNTIME_ROOT"
    find . -type f ! -path "./$INTEGRITY_RELATIVE" -print0 | LC_ALL=C sort -z |
        xargs -0 shasum -a 256
) > "$EXPECTED_FILES"

if ! cmp -s "$INTEGRITY_PATH" "$EXPECTED_FILES"; then
    echo "Runtime file inventory is incomplete, duplicated, stale, or corrupted." >&2
    exit 1
fi

file_count=$(wc -l < "$INTEGRITY_PATH" | tr -d ' ')
link_count=$(wc -l < "$LINKS_PATH" | tr -d ' ')
mode_count=$(wc -l < "$MODES_PATH" | tr -d ' ')
echo "PASS: runtime integrity exactly covers $file_count files, $link_count symlinks, and $mode_count modes."
