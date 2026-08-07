#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
MANIFEST="$REPOSITORY_ROOT/packaging/runtime-provenance.json"
SOURCE_ARCHIVE=${1:-}
MANIFEST_XML=$(mktemp "${TMPDIR:-/tmp}/secunda-provenance.XXXXXX")

cleanup() {
    rm -f "$MANIFEST_XML"
}
trap cleanup EXIT

/usr/bin/plutil -convert xml1 -o "$MANIFEST_XML" "$MANIFEST"

patch_index=0
patch_count=0
while patch_file=$(/usr/libexec/PlistBuddy \
    -c "Print :appliedPatches:${patch_index}:file" "$MANIFEST_XML" 2>/dev/null); do
    patch_sha256=$(/usr/libexec/PlistBuddy \
        -c "Print :appliedPatches:${patch_index}:sha256" "$MANIFEST_XML")
    patch_path="$REPOSITORY_ROOT/$patch_file"
    if [[ ! -f "$patch_path" ]]; then
        echo "Manifest patch is missing: $patch_file" >&2
        exit 1
    fi
    actual_patch_sha256=$(shasum -a 256 "$patch_path" | awk '{print $1}')
    if [[ "$actual_patch_sha256" != "$patch_sha256" ]]; then
        echo "Manifest patch checksum mismatch: $patch_file" >&2
        exit 1
    fi
    (( patch_count += 1 ))
    (( patch_index += 1 ))
done

if (( patch_count == 0 )); then
    echo "Runtime provenance contains no applied patches." >&2
    exit 1
fi

if [[ -n "$SOURCE_ARCHIVE" ]]; then
    expected_source_sha256=$(/usr/libexec/PlistBuddy \
        -c 'Print :sourceArchive:sha256' "$MANIFEST_XML")
    actual_source_sha256=$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{print $1}')
    if [[ "$actual_source_sha256" != "$expected_source_sha256" ]]; then
        echo "Source archive checksum mismatch." >&2
        exit 1
    fi
fi

echo "PASS: source provenance verified ($patch_count patches)."
