#!/bin/zsh
set -euo pipefail

typeset -a evidence_files
typeset -a runtime_paths
typeset -a root_process_ids
typeset -a scan_files
typeset -a report_lines

report_path=""
temporary_root=""

usage() {
    cat <<'EOF'
Usage:
  SECUNDA_SOURCE_ONLY=1 ./scripts/verify-source-only-provenance.sh \
    --runtime PATH [--pid PID] [--evidence FILE]... [--report FILE]

Verifies that a source-only acceptance run does not reference or load the
proprietary CrossOver application or known proprietary graphics payloads.

Inputs:
  --runtime PATH   Source-built Wine executable used by the run. Repeatable.
  --pid PID        Live Wine/Steam process whose descendants and mapped files
                   should be inspected. Repeatable.
  --evidence FILE  Existing text evidence, such as a sanitized environment,
                   process snapshot, vmmap, lsof, or launch record. Repeatable.
  --report FILE    Write the collected, non-secret runtime/process provenance.
  --help           Show this help.

The explicit SECUNDA_SOURCE_ONLY=1 environment marker is mandatory. The check
does not read or record complete process environments because those can contain
account or session secrets. Pass only sanitized environment evidence.
EOF
}

fail() {
    print -u2 -- "SOURCE-ONLY PROVENANCE FAILED: $*"
    exit 1
}

cleanup() {
    if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
        rm -rf -- "$temporary_root"
    fi
}

trap cleanup EXIT

canonical_path() {
    local input_path=$1
    print -r -- "${input_path:A}"
}

append_report_line() {
    report_lines+=("$1")
}

add_scan_text() {
    local label=$1
    local text_value=$2
    local output_file="$temporary_root/value-${#scan_files}.txt"

    print -r -- "$label=$text_value" > "$output_file"
    scan_files+=("$output_file")
}

validate_runtime() {
    local requested_path=$1
    local resolved_path
    local metadata_file="$temporary_root/runtime-${#scan_files}.txt"
    local strings_file="$temporary_root/runtime-strings-${#scan_files}.txt"

    [[ -f "$requested_path" ]] || fail "runtime executable does not exist: $requested_path"
    [[ -x "$requested_path" ]] || fail "runtime is not executable: $requested_path"

    resolved_path=$(canonical_path "$requested_path")
    append_report_line "RUNTIME_EXECUTABLE=$resolved_path"
    add_scan_text "RUNTIME_EXECUTABLE" "$resolved_path"

    {
        print -r -- "RUNTIME_EXECUTABLE=$resolved_path"
        file -- "$resolved_path"
        if file -- "$resolved_path" | grep -q 'Mach-O'; then
            otool -L "$resolved_path"
        fi
    } > "$metadata_file"
    scan_files+=("$metadata_file")

    if command -v strings >/dev/null 2>&1; then
        strings -a -- "$resolved_path" > "$strings_file"
        scan_files+=("$strings_file")
    fi
}

validate_evidence_file() {
    local evidence_path=$1
    local resolved_path

    [[ -f "$evidence_path" ]] || fail "evidence file does not exist: $evidence_path"
    [[ -s "$evidence_path" ]] || fail "evidence file is empty: $evidence_path"

    resolved_path=$(canonical_path "$evidence_path")
    add_scan_text "EVIDENCE_FILE" "$resolved_path"
    scan_files+=("$resolved_path")
}

descendant_processes() {
    local root_pid=$1
    local -a pending
    local -a discovered
    local current_pid
    local child_pid

    pending=("$root_pid")
    while (( ${#pending} > 0 )); do
        current_pid=${pending[1]}
        shift pending
        discovered+=("$current_pid")

        while IFS= read -r child_pid; do
            [[ -n "$child_pid" ]] || continue
            pending+=("$child_pid")
        done < <(pgrep -P "$current_pid" 2>/dev/null || true)
    done

    print -l -- "${discovered[@]}"
}

capture_process_provenance() {
    local root_pid=$1
    local process_pid
    local command_name
    local process_file="$temporary_root/process-$root_pid.txt"
    local mapped_file="$temporary_root/mapped-$root_pid.txt"
    local mapped_count=0

    [[ "$root_pid" == <-> ]] || fail "PID must be numeric: $root_pid"
    ps -p "$root_pid" -o pid= >/dev/null 2>&1 || fail "process is not running: $root_pid"
    command -v lsof >/dev/null 2>&1 || fail "lsof is required when --pid is used"

    : > "$process_file"
    : > "$mapped_file"

    while IFS= read -r process_pid; do
        [[ -n "$process_pid" ]] || continue
        command_name=$(ps -ww -p "$process_pid" -o comm= 2>/dev/null || true)
        [[ -n "$command_name" ]] || continue

        print -r -- "PROCESS pid=$process_pid executable=$command_name" >> "$process_file"
        append_report_line "PROCESS pid=$process_pid executable=$command_name"

        if lsof -n -P -a -p "$process_pid" -Ffn 2>/dev/null \
            | awk '
                /^f/ { mapped = ($0 == "ftxt" || $0 == "fmem") }
                /^n/ && mapped { sub(/^n/, "LOADED_PATH="); print }
            ' >> "$mapped_file"; then
            mapped_count=$((mapped_count + 1))
        fi
    done < <(descendant_processes "$root_pid")

    (( mapped_count > 0 )) || fail "could not inspect mapped files for process tree rooted at $root_pid"
    [[ -s "$mapped_file" ]] || fail "no mapped files were captured for process tree rooted at $root_pid"

    scan_files+=("$process_file" "$mapped_file")
    while IFS= read -r command_name; do
        append_report_line "$command_name"
    done < "$mapped_file"
}

scan_selected_environment() {
    local variable_name
    local variable_value
    local -a path_variables
    local -a forbidden_variables

    path_variables=(
        PATH
        WINEPREFIX
        WINELOADER
        WINESERVER
        WINEDLLPATH
        DYLD_LIBRARY_PATH
        DYLD_FALLBACK_LIBRARY_PATH
        SECUNDA_REPOSITORY_ROOT
        SECUNDA_RUNTIME_ROOT
        SECUNDA_RUNTIME_EXECUTABLE
    )

    forbidden_variables=(
        CX_BOTTLE
        CX_BOTTLE_PATH
        CX_ROOT
        CX_APP
        SECUNDA_CROSSOVER_APP
    )

    for variable_name in "${forbidden_variables[@]}"; do
        variable_value=""
        if (( ${+parameters[$variable_name]} )); then
            variable_value=${(P)variable_name}
        fi
        [[ -z "$variable_value" ]] || fail "$variable_name is set; CrossOver-specific environment is forbidden"
    done

    for variable_name in "${path_variables[@]}"; do
        variable_value=""
        if (( ${+parameters[$variable_name]} )); then
            variable_value=${(P)variable_name}
        fi
        [[ -n "$variable_value" ]] || continue
        add_scan_text "ENV_$variable_name" "$variable_value"
        if [[ "$variable_name" != "PATH" ]]; then
            append_report_line "ENV_$variable_name=$variable_value"
        fi
    done
}

scan_forbidden_references() {
    local scan_file
    local rule_index
    local match
    local -a rule_names
    local -a rule_patterns

    rule_names=(
        "CrossOver application path"
        "CrossOver SharedSupport path"
        "CrossOver bundle identity"
        "CrossOver bottle storage"
        "CrossOver helper executable"
        "CrossOver hosted executable identity"
        "Apple GPTK payload directory"
        "Apple Game Porting Toolkit payload"
        "proprietary d3dshared library"
        "proprietary D3DMetal framework"
    )
    rule_patterns=(
        'CrossOver\.app(/|[[:space:]"]|$)'
        'Contents/SharedSupport/CrossOver(/|[[:space:]"]|$)'
        'com\.codeweavers\.CrossOver'
        'Application Support/CrossOver(/|[[:space:]"]|$)'
        '(^|/)(cxrun|cxoffice|cxstart|cxbottle|cxmenu|winewrapper)([./[:space:]"]|$)'
        'CrossOver-Hosted Application'
        '(^|[/[:space:]"=])apple_gptk([/[:space:]"=]|$)'
        'Game[[:space:]]*Porting[[:space:]]*Toolkit'
        'libd3dshared\.dylib'
        '(D3DMetal\.framework|libD3DMetal\.dylib)'
    )

    for scan_file in "${scan_files[@]}"; do
        for (( rule_index = 1; rule_index <= ${#rule_names}; rule_index++ )); do
            match=$(LC_ALL=C grep -E -i -n -m 1 -- "${rule_patterns[$rule_index]}" "$scan_file" 2>/dev/null || true)
            if [[ -n "$match" ]]; then
                print -u2 -- "Forbidden provenance: ${rule_names[$rule_index]}"
                print -u2 -- "Evidence: $scan_file:$match"
                return 1
            fi
        done
    done
}

write_report() {
    local destination=$1
    local destination_parent=${destination:h}
    local resolved_destination
    local staged_report="$temporary_root/source-only-provenance.txt"

    [[ -d "$destination_parent" ]] || fail "report parent directory does not exist: $destination_parent"
    resolved_destination=$(canonical_path "$destination")

    {
        print -r -- "SECUNDA_SOURCE_ONLY=1"
        print -r -- "PROVENANCE_FORMAT=1"
        print -l -- "${report_lines[@]}"
    } > "$staged_report"

    cp -- "$staged_report" "$resolved_destination"
    print -- "Source-only provenance report: $resolved_destination"
}

while (( $# > 0 )); do
    case "$1" in
        --runtime)
            (( $# >= 2 )) || fail "--runtime requires a path"
            runtime_paths+=("$2")
            shift 2
            ;;
        --pid)
            (( $# >= 2 )) || fail "--pid requires a process ID"
            root_process_ids+=("$2")
            shift 2
            ;;
        --evidence)
            (( $# >= 2 )) || fail "--evidence requires a file"
            evidence_files+=("$2")
            shift 2
            ;;
        --report)
            (( $# >= 2 )) || fail "--report requires a file"
            report_path=$2
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

[[ "${SECUNDA_SOURCE_ONLY:-0}" == "1" ]] \
    || fail "set SECUNDA_SOURCE_ONLY=1 before running this acceptance gate"

(( ${#runtime_paths} + ${#root_process_ids} + ${#evidence_files} > 0 )) \
    || fail "provide at least one --runtime, --pid, or --evidence input"

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/secunda-provenance.XXXXXX")
append_report_line "CHECKED_AT_UTC=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
scan_selected_environment

for runtime_path in "${runtime_paths[@]}"; do
    validate_runtime "$runtime_path"
done

for evidence_file in "${evidence_files[@]}"; do
    validate_evidence_file "$evidence_file"
done

for root_process_id in "${root_process_ids[@]}"; do
    capture_process_provenance "$root_process_id"
done

scan_forbidden_references \
    || fail "proprietary runtime contamination was detected"

if [[ -n "$report_path" ]]; then
    write_report "$report_path"
fi

print -- "PASS: source-only provenance contains no forbidden runtime references."
