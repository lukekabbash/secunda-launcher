#!/bin/zsh -f
set -euo pipefail

label="SNAPSHOT"
typeset -a shader_roots
typeset -a metal_roots

usage() {
    cat <<'EOF'
Usage: ./scripts/snapshot-dxmt-cache.sh [--label SAFE_LABEL] \
  [--shader-root PATH]... [--metal-root PATH]...

Prints aggregate DXMT shader-cache and Metal pipeline-cache file statistics.
It follows no symlinks and emits neither input paths, cache filenames, nor file
contents. With no roots, it prints a NOT_REQUESTED result.
EOF
}

fail() {
    print -u2 -- "DXMT CACHE SNAPSHOT FAILED: $*"
    exit 1
}

while (( $# > 0 )); do
    case "$1" in
        --label)
            (( $# >= 2 )) || fail "--label requires a value"
            label=$2
            shift 2
            ;;
        --shader-root)
            (( $# >= 2 )) || fail "--shader-root requires a path"
            shader_roots+=("$2")
            shift 2
            ;;
        --metal-root)
            (( $# >= 2 )) || fail "--metal-root requires a path"
            metal_roots+=("$2")
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

[[ "$label" == [A-Z]* && "$label" != *[^A-Z0-9_]* ]] \
    || fail "--label must be an uppercase evidence key"
if (( ${#shader_roots} == 0 && ${#metal_roots} == 0 )); then
    print -r -- "${label}_CACHE_RESULT=NOT_REQUESTED"
    exit 0
fi

typeset -A seen_shader_roots
typeset -A seen_metal_roots
file_path=""
base_name=""
file_metrics=""
file_bytes=0
file_mtime=0
dxmt_count=0
dxmt_bytes=0
metal_count=0
metal_bytes=0
newest_mtime=0

for root in "${shader_roots[@]}"; do
    root=${root:A}
    [[ -d "$root" ]] || fail "a shader-cache root does not exist"
    [[ -z "${seen_shader_roots[$root]:-}" ]] || continue
    seen_shader_roots[$root]=1

    while IFS= read -r -d $'\0' file_path; do
        base_name=${file_path:t}
        [[ "$base_name" == shaders_*.db* ]] || continue
        file_metrics=$(/usr/bin/stat -f '%z %m' -- "$file_path") \
            || fail "could not inspect a cache file"
        read -r file_bytes file_mtime <<< "$file_metrics"
        dxmt_count=$((dxmt_count + 1))
        dxmt_bytes=$((dxmt_bytes + file_bytes))

        if (( file_mtime > newest_mtime )); then
            newest_mtime=$file_mtime
        fi
    done < <(/usr/bin/find "$root" -type f -print0)
done

for root in "${metal_roots[@]}"; do
    root=${root:A}
    [[ -d "$root" ]] || fail "a Metal-cache root does not exist"
    [[ -z "${seen_metal_roots[$root]:-}" ]] || continue
    seen_metal_roots[$root]=1

    while IFS= read -r -d $'\0' file_path; do
        file_metrics=$(/usr/bin/stat -f '%z %m' -- "$file_path") \
            || fail "could not inspect a cache file"
        read -r file_bytes file_mtime <<< "$file_metrics"
        metal_count=$((metal_count + 1))
        metal_bytes=$((metal_bytes + file_bytes))

        if (( file_mtime > newest_mtime )); then
            newest_mtime=$file_mtime
        fi
    done < <(/usr/bin/find "$root" -type f -print0)
done

print -r -- "${label}_CACHE_RESULT=PASS"
print -r -- "${label}_DXMT_SHADER_CACHE_FILE_COUNT=$dxmt_count"
print -r -- "${label}_DXMT_SHADER_CACHE_BYTES=$dxmt_bytes"
print -r -- "${label}_METAL_PIPELINE_FILE_COUNT=$metal_count"
print -r -- "${label}_METAL_PIPELINE_BYTES=$metal_bytes"
print -r -- "${label}_NEWEST_CACHE_MTIME_EPOCH=$newest_mtime"
