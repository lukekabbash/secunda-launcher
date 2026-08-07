#!/bin/zsh -f
set -u
setopt pipefail

readonly EXPECTED_DXMT_VERSION="0.80"
readonly EXPECTED_PROVENANCE_SHA256="35e501d53894c57a262c5c7de63556edfd38ea60b57217e6c3043b142ee794db"
readonly MINIMUM_SAVE_BYTES=4096
readonly READINESS_SCRIPT_DIR="${0:A:h}"
readonly READINESS_REPOSITORY_ROOT="${READINESS_SCRIPT_DIR:h}"

typeset runtime_root=""
typeset prefix_root=""
typeset bottles_root=""
typeset -ir synthetic_fixture=0
typeset -i pass_count=0
typeset -i warning_count=0
typeset -i failure_count=0

usage() {
    print -r -- "Usage:"
    print -r -- "  ./scripts/verify-skyrim-readiness.sh \\"
    print -r -- "    --runtime PATH --prefix PATH --bottles-root PATH"
    print
    print -r -- "Performs a read-only Skyrim readiness audit of a packaged source"
    print -r -- "runtime and one explicit Secunda-managed Wine prefix."
    print
    print -r -- "The verifier never runs Wine, Steam, Skyrim, registry tools, or"
    print -r -- "process-inspection tools. It never reads Steam login files, process"
    print -r -- "environments, or process argument lists, and it writes no report."
}

record_pass() {
    pass_count=$((pass_count + 1))
    print -r -- "PASS: $1"
}

record_warning() {
    warning_count=$((warning_count + 1))
    print -u2 -r -- "WARNING: $1"
}

record_failure() {
    failure_count=$((failure_count + 1))
    print -u2 -r -- "FAIL: $1"
}

is_contained() {
    local candidate=$1
    local root=$2
    local resolved_candidate=$candidate:A
    local resolved_root=$root:A

    [[ "$resolved_candidate" == "$resolved_root" || "$resolved_candidate" == "$resolved_root"/* ]]
}

is_narrow_audit_root() {
    local root=$1
    local parent=$root:h

    [[ "$root" == /* \
        && "$root" != "/" \
        && "$parent" != "/" \
        && "$parent:h" != "/" ]] || return 1

    case "$root" in
        /Applications|/Library|/System|/Users|/Volumes|/private|/tmp|/usr|/var)
            return 1
            ;;
    esac
    case "$root:t" in
        Applications|Desktop|Documents|Downloads)
            return 1
            ;;
    esac
    return 0
}

path_has_symlink_component() {
    local file_path=$1
    local owner_root=$2
    local relative_path
    local component
    local current_path=$owner_root
    local -a components

    [[ "$file_path" == "$owner_root"/* ]] || return 0
    relative_path=${file_path#"$owner_root"/}
    components=("${(@s:/:)relative_path}")
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        current_path="$current_path/$component"
        [[ -L "$current_path" ]] && return 0
    done
    return 1
}

is_private_metadata_file() {
    local file_path=$1
    local owner_root=$2

    [[ -f "$file_path" && ! -L "$file_path" ]] \
        && is_contained "$file_path" "$owner_root" \
        && ! path_has_symlink_component "$file_path" "$owner_root"
}


readonly READINESS_LIB_DIR="$READINESS_SCRIPT_DIR/lib"
load_readiness_library() {
    local library_path=$1

    if ! is_private_metadata_file "$library_path" "$READINESS_SCRIPT_DIR"; then
        print -u2 -- "FAIL: readiness validation library is missing or linked"
        exit 1
    fi
    if ! source "$library_path"; then
        print -u2 -- "FAIL: readiness validation library could not be loaded"
        exit 1
    fi
}

load_readiness_library "$READINESS_LIB_DIR/skyrim-readiness-runtime.zsh"
load_readiness_library "$READINESS_LIB_DIR/skyrim-readiness-prefix.zsh"

read_unsigned_le() {
    local file_path=$1
    local offset=$2
    local width=$3
    local value

    value=$(/usr/bin/od -An -j "$offset" -N "$width" -tu"$width" \
        "$file_path" 2>/dev/null | /usr/bin/tr -d '[:space:]') || return 1
    [[ "$value" == <-> ]] || return 1
    print -r -- "$value"
}

has_coherent_pe_structure() {
    local payload=$1
    local byte_count=$2
    local pe_offset
    local machine
    local section_count
    local optional_size
    local optional_magic
    local entry_point
    local image_size
    local headers_size
    local section_table
    local section_table_end
    local section_index
    local section_offset
    local raw_size
    local raw_offset
    local -i coherent_section_count=0

    pe_offset=$(read_unsigned_le "$payload" 60 4) || return 1
    (( pe_offset >= 64 && pe_offset <= byte_count - 264 )) || return 1
    machine=$(read_unsigned_le "$payload" $((pe_offset + 4)) 2) || return 1
    section_count=$(read_unsigned_le "$payload" $((pe_offset + 6)) 2) || return 1
    optional_size=$(read_unsigned_le "$payload" $((pe_offset + 20)) 2) || return 1
    optional_magic=$(read_unsigned_le "$payload" $((pe_offset + 24)) 2) || return 1

    if (( machine == 332 )); then
        (( optional_magic == 267 && optional_size >= 224 )) || return 1
    elif (( machine == 34404 )); then
        (( optional_magic == 523 && optional_size >= 240 )) || return 1
    else
        return 1
    fi
    (( section_count >= 1 && section_count <= 96 )) || return 1

    entry_point=$(read_unsigned_le "$payload" $((pe_offset + 40)) 4) || return 1
    image_size=$(read_unsigned_le "$payload" $((pe_offset + 80)) 4) || return 1
    headers_size=$(read_unsigned_le "$payload" $((pe_offset + 84)) 4) || return 1
    section_table=$((pe_offset + 24 + optional_size))
    section_table_end=$((section_table + section_count * 40))
    (( entry_point > 0 && entry_point < image_size \
        && headers_size >= section_table_end && headers_size <= byte_count \
        && section_table_end <= byte_count )) || return 1

    for (( section_index = 0; section_index < section_count; section_index++ )); do
        section_offset=$((section_table + section_index * 40))
        raw_size=$(read_unsigned_le "$payload" $((section_offset + 16)) 4) || return 1
        raw_offset=$(read_unsigned_le "$payload" $((section_offset + 20)) 4) || return 1
        if (( raw_size > 0 && raw_offset >= headers_size \
            && raw_offset <= byte_count && raw_size <= byte_count - raw_offset )); then
            coherent_section_count=$((coherent_section_count + 1))
        fi
    done
    (( coherent_section_count > 0 ))
}

validate_pe_payload() {
    local label=$1
    local payload=$2
    local minimum_bytes=$3
    local description
    local byte_count

    description=$(/usr/bin/file -b "$payload" 2>/dev/null) || true
    byte_count=$(/usr/bin/stat -f '%z' "$payload" 2>/dev/null) || true
    if [[ "$description" != *PE32* || "$byte_count" != <-> \
        || $byte_count -lt $minimum_bytes ]] \
        || ! has_coherent_pe_structure "$payload" "$byte_count"; then
        record_failure "$label is not a plausible packaged Windows payload"
        return 1
    fi
    record_pass "$label has a plausible PE identity, section layout, and size"
}

# Match the launcher's preferred Windows-user order. If none of those users
# exists, retain a fail-closed fallback rather than guessing between profiles.
select_windows_user_directory() {
    local users_root="$prefix_root/drive_c/users"
    local host_user=""
    local preferred_name
    local candidate
    local candidate_name
    local normalized_name
    local -a preferred_names
    local -a candidates

    [[ -d "$users_root" && ! -L "$users_root" ]] || return 1
    host_user=$(/usr/bin/id -un 2>/dev/null) || host_user=""
    preferred_names=(steamuser "$host_user" secunda)
    for preferred_name in "${preferred_names[@]}"; do
        [[ -n "$preferred_name" ]] || continue
        candidate="$users_root/$preferred_name"
        if [[ -e "$candidate" || -L "$candidate" ]]; then
            print -r -- "$candidate"
            return 0
        fi
    done

    candidates=()
    for candidate in "$users_root"/*(N); do
        [[ -d "$candidate" ]] || continue
        candidate_name=$candidate:t
        normalized_name=${candidate_name:l}
        case "$normalized_name" in
            "all users"|"default"|"default user"|"public") continue ;;
        esac
        candidates+=("$candidate")
    done

    (( ${#candidates[@]} == 1 )) || return 1
    print -r -- "${candidates[1]}"
}

is_plausible_skyrim_save() {
    local save_path=$1
    local byte_count
    local signature
    local header_size

    [[ -f "$save_path" && ! -L "$save_path" ]] || return 1
    is_contained "$save_path" "$prefix_root" || return 1
    byte_count=$(/usr/bin/stat -f '%z' "$save_path" 2>/dev/null) || return 1
    [[ "$byte_count" == <-> && $byte_count -ge $MINIMUM_SAVE_BYTES ]] || return 1
    signature=$(LC_ALL=C /usr/bin/head -c 13 "$save_path" 2>/dev/null) || return 1
    [[ "$signature" == "TESV_SAVEGAME" ]] || return 1
    header_size=$(read_unsigned_le "$save_path" 13 4) || return 1
    (( header_size >= 16 && header_size <= byte_count - 17 ))
}

is_plausible_skyrim_master() {
    local master_path=$1
    local byte_count
    local signature
    local record_size
    local first_subrecord

    [[ -f "$master_path" && ! -L "$master_path" ]] || return 1
    is_contained "$master_path" "$prefix_root" || return 1
    byte_count=$(/usr/bin/stat -f '%z' "$master_path" 2>/dev/null) || return 1
    [[ "$byte_count" == <-> && $byte_count -ge 1048576 ]] || return 1
    signature=$(LC_ALL=C /usr/bin/head -c 4 "$master_path" 2>/dev/null) || return 1
    [[ "$signature" == "TES4" ]] || return 1
    record_size=$(read_unsigned_le "$master_path" 4 4) || return 1
    (( record_size >= 18 && record_size <= byte_count - 24 )) || return 1
    first_subrecord=$(/bin/dd if="$master_path" bs=1 skip=24 count=4 status=none 2>/dev/null) \
        || return 1
    [[ "$first_subrecord" == "HEDR" ]]
}

validate_installed_master_structure() {
    local steam_root=""
    local candidate
    local library_root
    local manifest
    local install_directory
    local game_root
    local component
    local master_path
    local -a steam_candidates

    steam_candidates=(
        "$prefix_root/drive_c/Program Files (x86)/Steam"
        "$prefix_root/drive_c/Program Files/Steam"
    )
    for candidate in "${steam_candidates[@]}"; do
        if [[ -f "$candidate/steam.exe" && ! -L "$candidate/steam.exe" ]]; then
            steam_root=$candidate
            break
        fi
    done
    [[ -n "$steam_root" ]] || return

    discover_steam_libraries "$steam_root"
    for library_root in "${discovered_steam_libraries[@]}"; do
        manifest="$library_root/steamapps/appmanifest_489830.acf"
        is_private_metadata_file "$manifest" "$prefix_root" || continue
        [[ "$(vdf_first_value "$manifest" appid)" == "489830" ]] || continue
        [[ "$(vdf_first_value "$manifest" StateFlags)" == "4" ]] || continue
        manifest_download_is_complete "$manifest" BytesDownloaded BytesToDownload || continue
        manifest_download_is_complete "$manifest" BytesStaged BytesToStage || continue
        install_directory=$(vdf_first_value "$manifest" installdir)
        safe_relative_components "$install_directory" || continue
        game_root="$library_root/steamapps/common"
        for component in "${safe_relative_components_result[@]}"; do
            game_root="$game_root/$component"
        done
        master_path="$game_root/Data/Skyrim.esm"
        if is_plausible_skyrim_master "$master_path"; then
            record_pass "Skyrim baseline data has a plausible TES4 record structure"
            return
        fi
    done
    record_failure "Skyrim baseline data does not have a plausible TES4 record structure"
}

validate_documents_boundary() {
    setopt local_options glob_dots

    local user_directory
    local documents
    local my_games
    local game_profile
    local saves
    local profile_link
    local save_path
    local -i plausible_save_count=0
    local -a existing_saves

    user_directory=$(select_windows_user_directory) || {
        record_failure "prefix does not have one unambiguous launcher-selected Windows user directory"
        return
    }
    if [[ ! -d "$user_directory" || -L "$user_directory" ]] \
        || ! is_contained "$user_directory" "$prefix_root"; then
        record_failure "selected Windows user directory is not private to the prefix"
        return
    fi

    documents="$user_directory/Documents"
    validate_private_path "Windows Documents directory" "$documents" yes || return
    record_pass "Windows Documents is a real directory inside the managed prefix"

    my_games="$documents/My Games"
    game_profile="$my_games/Skyrim Special Edition"
    saves="$game_profile/Saves"

    if [[ -e "$my_games" || -L "$my_games" ]]; then
        validate_private_path "My Games directory" "$my_games" yes || return
    fi
    if [[ -e "$game_profile" || -L "$game_profile" ]]; then
        validate_private_path "Skyrim profile directory" "$game_profile" yes || return
        for profile_link in "$game_profile"/**/*(@N); do
            record_failure "Skyrim profile contains a symbolic link"
            return
        done
    fi
    if [[ -e "$saves" || -L "$saves" ]]; then
        validate_private_path "Skyrim save directory" "$saves" yes || return
        existing_saves=("$saves"/*.ess(.N))
        for save_path in "${existing_saves[@]}"; do
            is_plausible_skyrim_save "$save_path" \
                && plausible_save_count=$((plausible_save_count + 1))
        done
        if (( plausible_save_count > 0 )); then
            record_pass "at least one plausible non-empty Skyrim save exists inside private Documents"
            record_warning "static save structure does not prove successful in-game save and reload"
        elif (( ${#existing_saves[@]} > 0 )); then
            record_warning "Skyrim save directory has .ess files, but none has a plausible non-empty save structure"
        else
            record_warning "Skyrim save directory has no regular .ess save; persistence was not proven"
        fi
    else
        record_warning "no Skyrim save directory exists yet; save persistence was not proven"
    fi

    local host_root_mapping="$prefix_root/dosdevices/z:"
    if [[ -L "$host_root_mapping" ]] && ! is_contained "$host_root_mapping" "$prefix_root"; then
        record_warning "Wine exposes a host filesystem mapping; private Documents is not a full prefix sandbox"
    fi
}

validate_pinned_provenance() {
    local manifest="$runtime_root/share/secunda/runtime-provenance.json"
    local canonical_manifest="$READINESS_REPOSITORY_ROOT/packaging/runtime-provenance.json"
    local manifest_hash=""
    local canonical_hash=""

    is_private_metadata_file "$manifest" "$runtime_root" || return
    if [[ ! -f "$canonical_manifest" || -L "$canonical_manifest" ]]; then
        record_failure "canonical source-runtime provenance is unavailable"
        return
    fi

    manifest_hash=$(/usr/bin/shasum -a 256 "$manifest" 2>/dev/null \
        | /usr/bin/awk '{print tolower($1)}')
    canonical_hash=$(/usr/bin/shasum -a 256 "$canonical_manifest" 2>/dev/null \
        | /usr/bin/awk '{print tolower($1)}')
    if [[ "$manifest_hash" != "$EXPECTED_PROVENANCE_SHA256" \
        || "$canonical_hash" != "$EXPECTED_PROVENANCE_SHA256" ]] \
        || ! /usr/bin/cmp -s "$manifest" "$canonical_manifest"; then
        record_failure "runtime provenance does not match the pinned canonical source manifest"
        return
    fi
    record_pass "runtime provenance exactly matches the pinned canonical JSON manifest"
}

validate_required_integrity() {
    local verifier="$READINESS_SCRIPT_DIR/verify-runtime-integrity.sh"
    local metadata_path
    local -a required_metadata

    required_metadata=(
        "$runtime_root/share/secunda/runtime-files.sha256"
        "$runtime_root/share/secunda/runtime-links.tsv"
        "$runtime_root/share/secunda/runtime-modes.tsv"
    )
    for metadata_path in "${required_metadata[@]}"; do
        if ! is_private_metadata_file "$metadata_path" "$runtime_root"; then
            record_failure "runtime exact integrity metadata is missing, linked, or external"
            return
        fi
    done
    if [[ ! -x "$verifier" || -L "$verifier" ]]; then
        record_failure "runtime exact integrity verifier is unavailable"
        return
    fi
    if "$verifier" "$runtime_root" >/dev/null 2>&1; then
        record_pass "runtime integrity exactly covers files, symlinks, and handoff modes"
    else
        record_failure "runtime exact integrity inventories do not verify"
    fi
}

run_validator() {
    local validator_name=$1
    shift

    if ! "$@"; then
        record_failure "readiness validator did not complete: $validator_name"
    fi
}

while (( $# > 0 )); do
    case "$1" in
        --runtime)
            (( $# >= 2 )) || {
                print -u2 -- "Missing value for --runtime"
                exit 64
            }
            runtime_root=$2
            shift 2
            ;;
        --prefix)
            (( $# >= 2 )) || {
                print -u2 -- "Missing value for --prefix"
                exit 64
            }
            prefix_root=$2
            shift 2
            ;;
        --bottles-root)
            (( $# >= 2 )) || {
                print -u2 -- "Missing value for --bottles-root"
                exit 64
            }
            bottles_root=$2
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print -u2 -- "Unknown argument: $1"
            usage >&2
            exit 64
            ;;
    esac
done

if [[ -z "$runtime_root" || -z "$prefix_root" || -z "$bottles_root" ]]; then
    usage >&2
    exit 64
fi

if [[ ! -d "$runtime_root" ]]; then
    print -u2 -- "FAIL: runtime root does not exist"
    exit 1
fi
if [[ ! -d "$prefix_root" ]]; then
    print -u2 -- "FAIL: prefix root does not exist"
    exit 1
fi
if [[ ! -d "$bottles_root" ]]; then
    print -u2 -- "FAIL: managed bottles root does not exist"
    exit 1
fi

typeset -i prefix_was_symlink=0
typeset -i runtime_was_symlink=0
typeset -i bottles_was_symlink=0
[[ -L "$prefix_root" ]] && prefix_was_symlink=1
[[ -L "$runtime_root" ]] && runtime_was_symlink=1
[[ -L "$bottles_root" ]] && bottles_was_symlink=1

runtime_root=$runtime_root:A
prefix_root=$prefix_root:A
bottles_root=$bottles_root:A

if ! is_narrow_audit_root "$runtime_root" \
    || ! is_narrow_audit_root "$prefix_root" \
    || ! is_narrow_audit_root "$bottles_root"; then
    print -u2 -- "FAIL: audit roots are too broad"
    exit 1
fi
if [[ "$bottles_root:t" != "Bottles" || "$bottles_root:h:t" != "Secunda Launcher" ]]; then
    print -u2 -- "FAIL: production prefix is not under Secunda Launcher/Bottles"
    exit 1
fi
if [[ "$prefix_root:h" != "$bottles_root" ]]; then
    print -u2 -- "FAIL: prefix is not a direct child of the declared managed bottles root"
    exit 1
fi
if (( prefix_was_symlink || runtime_was_symlink || bottles_was_symlink )); then
    print -u2 -- "FAIL: runtime, prefix, and bottles roots must not be symbolic links"
    exit 1
fi
if is_contained "$runtime_root" "$bottles_root" \
    || is_contained "$bottles_root" "$runtime_root"; then
    print -u2 -- "FAIL: runtime and managed bottles roots must not overlap"
    exit 1
fi

if ! is_private_metadata_file "$prefix_root/system.reg" "$prefix_root" \
    || [[ ! -d "$prefix_root/drive_c" || -L "$prefix_root/drive_c" ]]; then
    record_failure "prefix is missing system.reg or drive_c"
else
    record_pass "Wine prefix structure is present"
fi

if [[ -x "$runtime_root/bin/wine64" || -x "$runtime_root/bin/wine" ]]; then
    record_pass "Wine launcher is present and executable"
else
    record_failure "runtime has no executable bin/wine64 or bin/wine"
fi
if [[ -x "$runtime_root/bin/wineserver" ]]; then
    record_pass "wineserver is present and executable"
else
    record_failure "runtime has no executable bin/wineserver"
fi

typeset -a required_runtime_components
required_runtime_components=(
    "lib/libfreetype.6.dylib"
    "lib/libgnutls.30.dylib"
    "lib/libgmp.10.dylib"
    "lib/libnettle.8.dylib"
    "lib/libhogweed.6.dylib"
    "lib/wine/x86_64-unix/winemetal.so"
    "lib/wine/x86_64-unix/winecoreaudio.so"
    "lib/wine/x86_64-windows/winecoreaudio.drv"
    "lib/wine/x86_64-windows/d3d11.dll"
    "lib/wine/x86_64-windows/dxgi.dll"
    "lib/wine/x86_64-windows/x3daudio1_6.dll"
    "lib/wine/x86_64-windows/x3daudio1_7.dll"
    "lib/wine/x86_64-windows/xaudio2_6.dll"
    "lib/wine/x86_64-windows/xaudio2_7.dll"
    "lib/wine/x86_64-windows/xinput1_3.dll"
    "lib/wine/x86_64-windows/tasklist.exe"
)
for relative_path in "${required_runtime_components[@]}"; do
    require_runtime_component "$relative_path"
done

run_validator "runtime provenance" validate_manifest
run_validator "pinned provenance" validate_pinned_provenance
run_validator "DXMT identity" validate_dxmt_version
run_validator "runtime integrity" validate_required_integrity
run_validator "audio overrides" validate_audio_overrides
run_validator "private Documents" validate_documents_boundary
run_validator "Steam and Skyrim install" validate_steam_and_game
run_validator "Skyrim master data" validate_installed_master_structure
run_validator "forbidden references" scan_forbidden_references

if (( failure_count > 0 )); then
    print -u2 -r -- \
        "SKYRIM READINESS FAILED: $failure_count gap(s), $warning_count warning(s), $pass_count check(s) passed."
    exit 1
fi

print -r -- \
    "SKYRIM READINESS PASSED: $pass_count checks passed with $warning_count warning(s)."
print -r -- \
    "This is a static, read-only readiness result; it is not evidence of a fresh-prefix Steam or Skyrim run."
