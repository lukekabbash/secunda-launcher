registry_has_builtin_override() {
    local registry_file=$1
    local override_name=$2

    /usr/bin/awk -v expected_name="$override_name" '
        BEGIN { expected_section = "[Software\\\\Wine\\\\DllOverrides]" }
        /^\[/ {
            section_line = $0
            sub(/\r$/, "", section_line)
            sub(/[[:space:]][0-9]+[[:space:]]*$/, "", section_line)
            in_section = (tolower(section_line) == tolower(expected_section))
            next
        }
        in_section {
            value_line = $0
            sub(/\r$/, "", value_line)
            expected = "\"" expected_name "\"=\"builtin\""
            if (tolower(value_line) == tolower(expected)) found = 1
        }
        END { exit(found ? 0 : 1) }
    ' "$registry_file"
}

validate_audio_overrides() {
    local user_registry="$prefix_root/user.reg"
    local override_name
    local -a required_overrides

    if ! is_private_metadata_file "$user_registry" "$prefix_root"; then
        record_failure "prefix user.reg is missing, linked, or external"
        return
    fi

    required_overrides=(x3daudio1_6 x3daudio1_7 xaudio2_6 xaudio2_7)
    for override_name in "${required_overrides[@]}"; do
        if registry_has_builtin_override "$user_registry" "$override_name"; then
            record_pass "Wine builtin override is configured: $override_name"
        else
            record_failure "Wine builtin override is missing or not builtin: $override_name"
        fi
    done
}

select_windows_user_directory() {
    local users_root="$prefix_root/drive_c/users"
    local preferred
    local candidate
    local candidate_name
    local normalized_name
    local -a candidates

    [[ -d "$users_root" ]] || return 1

    candidate="$users_root/steamuser"
    if [[ -d "$candidate" && ! -L "$candidate" ]]; then
        print -r -- "$candidate"
        return 0
    fi

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
    [[ ! -L "${candidates[1]}" ]] || return 1
    print -r -- "${candidates[1]}"
}

validate_private_path() {
    local path_label=$1
    local path_value=$2
    local must_exist=$3

    if [[ -L "$path_value" ]]; then
        record_failure "$path_label is a symbolic link"
        return 1
    fi
    if [[ ! -e "$path_value" ]]; then
        if [[ "$must_exist" == "yes" ]]; then
            record_failure "$path_label does not exist"
        fi
        return 1
    fi
    if [[ ! -d "$path_value" ]]; then
        record_failure "$path_label is not a directory"
        return 1
    fi
    if ! is_contained "$path_value" "$prefix_root"; then
        record_failure "$path_label resolves outside the managed prefix"
        return 1
    fi
    return 0
}

validate_documents_boundary() {
    setopt local_options glob_dots

    local user_directory
    local documents
    local my_games
    local game_profile
    local saves
    local profile_link
    local -a existing_saves

    user_directory=$(select_windows_user_directory) || {
        record_failure "prefix does not have one unambiguous private Windows user directory"
        return
    }
    if [[ -L "$user_directory" ]] || ! is_contained "$user_directory" "$prefix_root"; then
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
        if (( ${#existing_saves[@]} > 0 )); then
            record_pass "at least one regular Skyrim save exists inside private Documents"
            record_warning "static save presence does not prove successful in-game save and reload"
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


vdf_values() {
    local vdf_file=$1
    local expected_key=$2

    /usr/bin/awk -v expected_key="$expected_key" '
        {
            first = ""
            second = ""
            current = ""
            field_count = 0
            quoted = 0
            escaped = 0

            for (char_index = 1; char_index <= length($0); char_index++) {
                character = substr($0, char_index, 1)
                if (escaped) {
                    current = current character
                    escaped = 0
                } else if (quoted && character == "\\") {
                    escaped = 1
                } else if (character == "\"") {
                    if (quoted) {
                        field_count++
                        if (field_count == 1) first = current
                        if (field_count == 2) second = current
                        current = ""
                    }
                    quoted = !quoted
                } else if (quoted) {
                    current = current character
                }
            }

            if (field_count >= 2 && tolower(first) == tolower(expected_key)) {
                print second
            }
        }
    ' "$vdf_file"
}

vdf_first_value() {
    vdf_values "$1" "$2" | /usr/bin/sed -n '1p'
}

typeset -ga safe_relative_components_result

safe_relative_components() {
    local path_value=$1
    local normalized
    local component
    local -a split_components

    safe_relative_components_result=()
    [[ -n "$path_value" && "$path_value" != /* && "$path_value" != \\* ]] || return 1

    normalized=$(print -r -- "$path_value" | /usr/bin/tr '\\' '/')
    split_components=("${(@s:/:)normalized}")
    for component in "${split_components[@]}"; do
        [[ -n "$component" ]] || continue
        [[ "$component" != "." && "$component" != ".." && "$component" != *:* ]] || return 1
        safe_relative_components_result+=("$component")
    done
    (( ${#safe_relative_components_result[@]} > 0 ))
}

typeset -g mapped_library_result=""

map_windows_library() {
    local windows_path=$1
    local drive
    local separator
    local tail
    local base
    local component
    local candidate

    mapped_library_result=""
    (( ${#windows_path} >= 3 )) || return 1
    drive=${windows_path[1]}
    drive=${drive:l}
    [[ "$drive" == [a-z] && "${windows_path[2]}" == ":" ]] || return 1
    separator=${windows_path[3]}
    [[ "$separator" == "\\" || "$separator" == "/" ]] || return 1

    tail=${windows_path[4,-1]}
    safe_relative_components "$tail" || return 1
    if [[ "$drive" == "c" ]]; then
        base="$prefix_root/drive_c"
    else
        base="$prefix_root/dosdevices/$drive:"
    fi
    [[ -e "$base" ]] || return 1

    candidate=$base
    for component in "${safe_relative_components_result[@]}"; do
        candidate="$candidate/$component"
    done
    is_contained "$candidate" "$prefix_root" || return 1
    mapped_library_result=$candidate:A
}

typeset -ga discovered_steam_libraries

discover_steam_libraries() {
    local steam_root=$1
    local folders="$steam_root/steamapps/libraryfolders.vdf"
    local windows_path
    local resolved_library

    discovered_steam_libraries=()
    if is_contained "$steam_root" "$prefix_root"; then
        discovered_steam_libraries+=("$steam_root:A")
    fi

    if [[ -e "$folders" || -L "$folders" ]]; then
        if ! is_private_metadata_file "$folders" "$prefix_root"; then
            record_failure "Steam libraryfolders.vdf is linked or external"
            return
        fi
        while IFS= read -r windows_path; do
            map_windows_library "$windows_path" || continue
            resolved_library=$mapped_library_result
            (( ${discovered_steam_libraries[(Ie)$resolved_library]} > 0 )) \
                || discovered_steam_libraries+=("$resolved_library")
        done < <(vdf_values "$folders" path)
    fi
}

manifest_download_is_complete() {
    local manifest=$1
    local completed_key=$2
    local expected_key=$3
    local expected
    local completed

    expected=$(vdf_first_value "$manifest" "$expected_key")
    [[ -n "$expected" ]] || return 0
    completed=$(vdf_first_value "$manifest" "$completed_key")
    [[ "$expected" == <-> && "$completed" == <-> ]] || return 1
    (( completed >= expected ))
}

validate_pe_payload() {
    local label=$1
    local payload=$2
    local minimum_bytes=$3
    local description
    local byte_count

    (( synthetic_fixture )) && return 0
    description=$(/usr/bin/file -b "$payload" 2>/dev/null) || true
    byte_count=$(/usr/bin/stat -f '%z' "$payload" 2>/dev/null) || true
    if [[ "$description" != *PE32* || "$byte_count" != <-> \
        || $byte_count -lt $minimum_bytes ]]; then
        record_failure "$label is not a plausible packaged Windows payload"
        return 1
    fi
    record_pass "$label has a plausible PE identity and size"
}

typeset -g install_probe_reason=""
typeset -gi saw_skyrim_manifest=0

validate_skyrim_library() {
    local library_root=$1
    local app_manifest="$library_root/steamapps/appmanifest_489830.acf"
    local app_id
    local install_directory
    local state_flags
    local game_root
    local game_executable
    local skyrim_master
    local component

    if ! is_private_metadata_file "$app_manifest" "$prefix_root"; then
        return 1
    fi
    saw_skyrim_manifest=1

    app_id=$(vdf_first_value "$app_manifest" appid)
    if [[ "$app_id" != "489830" ]]; then
        install_probe_reason="Skyrim app manifest does not identify app 489830"
        return 1
    fi

    install_directory=$(vdf_first_value "$app_manifest" installdir)
    if ! safe_relative_components "$install_directory"; then
        install_probe_reason="Skyrim app manifest has an unsafe install directory"
        return 1
    fi

    state_flags=$(vdf_first_value "$app_manifest" StateFlags)
    if [[ "$state_flags" != "4" ]] \
        || ! manifest_download_is_complete "$app_manifest" BytesDownloaded BytesToDownload \
        || ! manifest_download_is_complete "$app_manifest" BytesStaged BytesToStage; then
        install_probe_reason="Skyrim app manifest does not report a complete installed state"
        return 1
    fi

    game_root="$library_root/steamapps/common"
    for component in "${safe_relative_components_result[@]}"; do
        game_root="$game_root/$component"
    done
    game_executable="$game_root/SkyrimSE.exe"
    if [[ ! -f "$game_executable" || -L "$game_executable" ]] \
        || ! is_contained "$game_executable" "$prefix_root"; then
        install_probe_reason="SkyrimSE.exe is missing from launcher-resolved, prefix-contained Steam libraries"
        return 1
    fi

    record_pass "Steam app manifest identifies Skyrim app 489830"
    record_pass "Steam app manifest provides a safe, launcher-resolved install directory"
    record_pass "Steam app manifest reports a complete installed state"
    record_pass "SkyrimSE.exe is present in a launcher-resolved, prefix-contained Steam library"
    validate_pe_payload "Skyrim executable" "$game_executable" 1048576 || return 1

    skyrim_master="$game_root/Data/Skyrim.esm"
    if [[ ! -f "$skyrim_master" || -L "$skyrim_master" ]] \
        || ! is_contained "$skyrim_master" "$prefix_root"; then
        install_probe_reason="Skyrim baseline data payload is missing or external"
        return 1
    fi
    if (( !synthetic_fixture )); then
        local master_bytes
        master_bytes=$(/usr/bin/stat -f '%z' "$skyrim_master" 2>/dev/null) || true
        if [[ "$master_bytes" != <-> || $master_bytes -lt 1048576 ]]; then
            install_probe_reason="Skyrim baseline data payload is implausibly small"
            return 1
        fi
    fi
    record_pass "Skyrim baseline data payload is present inside the managed prefix"
    return 0
}

validate_steam_and_game() {
    local steam_root=""
    local candidate
    local steam_executable
    local library_root
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

    if [[ -z "$steam_root" ]]; then
        record_failure "Steam is absent from both launcher-supported prefix locations"
        return
    fi
    steam_executable="$steam_root/steam.exe"
    if ! is_contained "$steam_executable" "$prefix_root"; then
        record_failure "Steam executable resolves outside the managed prefix"
        return
    fi
    record_pass "Steam is present at a launcher-supported in-prefix path"
    validate_pe_payload "Steam executable" "$steam_executable" 102400 || return

    install_probe_reason=""
    saw_skyrim_manifest=0
    discover_steam_libraries "$steam_root"
    for library_root in "${discovered_steam_libraries[@]}"; do
        validate_skyrim_library "$library_root" && return
    done

    if [[ -n "$install_probe_reason" ]]; then
        record_failure "$install_probe_reason"
    elif (( saw_skyrim_manifest )); then
        record_failure "Skyrim installation is incomplete in launcher-resolved Steam libraries"
    else
        record_failure "Steam app manifest for Skyrim is absent from launcher-resolved, prefix-contained libraries"
    fi
}
