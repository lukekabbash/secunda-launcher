#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
RUNTIME_ROOT=${1:-"$REPOSITORY_ROOT/Runtime/wine"}
RUNTIME_ROOT=${RUNTIME_ROOT:A}
MODE=${2:---fix}

if [[ ! -d "$RUNTIME_ROOT" || ! -x "$RUNTIME_ROOT/bin/wine" ]]; then
    echo "Incomplete Secunda runtime: $RUNTIME_ROOT" >&2
    exit 1
fi

case "$MODE" in
    --fix|--verify) ;;
    *)
        echo "Usage: $0 [runtime-root] [--fix|--verify]" >&2
        exit 64
        ;;
esac

runtime_rpath_for() {
    local runtime_file=$1
    case "$runtime_file" in
        "$RUNTIME_ROOT"/bin/*) print -- '@loader_path/../lib' ;;
        "$RUNTIME_ROOT"/lib/wine/*-unix/*) print -- '@loader_path/../../' ;;
        "$RUNTIME_ROOT"/lib/*) print -- '@loader_path/' ;;
        *) print -- '@loader_path/' ;;
    esac
}

list_rpaths() {
    otool -l "$1" 2>/dev/null | awk '
        /cmd LC_RPATH/ { awaiting_path = 1; next }
        awaiting_path && /path / { print $2; awaiting_path = 0 }
    '
}

has_rpath() {
    local runtime_file=$1
    local expected=$2
    list_rpaths "$runtime_file" | grep -Fqx -- "$expected"
}

is_macho() {
    file -b "$1" 2>/dev/null | grep -q 'Mach-O'
}

invalid_dependency_count=0
absolute_rpath_count=0
missing_local_rpath_count=0
fixed_file_count=0
mach_o_count=0

while IFS= read -r -d '' runtime_file; do
    is_macho "$runtime_file" || continue
    (( mach_o_count += 1 ))

    absolute_rpaths=()
    while IFS= read -r runtime_rpath; do
        [[ "$runtime_rpath" == /* ]] && absolute_rpaths+=("$runtime_rpath")
    done < <(list_rpaths "$runtime_file")

    file_changed=0
    if (( ${#absolute_rpaths[@]} > 0 )); then
        (( absolute_rpath_count += ${#absolute_rpaths[@]} ))
        if [[ "$MODE" == "--fix" ]]; then
            for runtime_rpath in "${absolute_rpaths[@]}"; do
                install_name_tool -delete_rpath "$runtime_rpath" "$runtime_file"
            done
            file_changed=1
        fi
    fi

    local_rpath=$(runtime_rpath_for "$runtime_file")
    if ! has_rpath "$runtime_file" "$local_rpath"; then
        (( missing_local_rpath_count += 1 ))
        if [[ "$MODE" == "--fix" ]]; then
            install_name_tool -add_rpath "$local_rpath" "$runtime_file"
            file_changed=1
        fi
    fi

    if [[ "$MODE" == "--fix" && $file_changed -eq 1 ]]; then
        codesign --force --sign - "$runtime_file" >/dev/null
        (( fixed_file_count += 1 ))
    fi

    while IFS= read -r dependency; do
        case "$dependency" in
            @*|/usr/lib/*|/System/Library/*|/Library/Apple/*) ;;
            /*)
                echo "Non-system absolute dependency: $runtime_file -> $dependency" >&2
                (( invalid_dependency_count += 1 ))
                ;;
        esac
    done < <(otool -L "$runtime_file" 2>/dev/null | tail -n +2 | awk '{print $1}')
done < <(find "$RUNTIME_ROOT" -type f -print0)

if (( invalid_dependency_count > 0 )); then
    echo "Runtime contains $invalid_dependency_count non-system absolute dependencies." >&2
    exit 1
fi

if [[ "$MODE" == "--verify" && $absolute_rpath_count -gt 0 ]]; then
    echo "Runtime contains $absolute_rpath_count absolute build RPATH entries." >&2
    exit 1
fi
if [[ "$MODE" == "--verify" && $missing_local_rpath_count -gt 0 ]]; then
    echo "Runtime contains $missing_local_rpath_count Mach-O files without their required local RPATH." >&2
    exit 1
fi

if [[ "$MODE" == "--fix" ]]; then
    "$0" "$RUNTIME_ROOT" --verify
    echo "Relocated $fixed_file_count of $mach_o_count Mach-O runtime files."
else
    echo "PASS: $mach_o_count Mach-O runtime files use distributable paths."
fi
