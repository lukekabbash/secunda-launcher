require_runtime_component() {
    local relative_path=$1
    local component_path="$runtime_root/$relative_path"

    if [[ ! -f "$component_path" ]]; then
        record_failure "missing runtime component: $relative_path"
        return
    fi
    if ! is_contained "$component_path" "$runtime_root"; then
        record_failure "runtime component escapes its package root: $relative_path"
        return
    fi
    record_pass "runtime component present: $relative_path"
}

manifest_value() {
    local key_path=$1
    /usr/bin/plutil -extract "$key_path" raw -o - \
        "$runtime_root/share/secunda/runtime-provenance.json" 2>/dev/null
}

component_version() {
    local expected_name=$1
    local component_count
    local component_index
    local component_name
    local component_value

    component_count=$(manifest_value components 2>/dev/null) || return 1
    [[ "$component_count" == <-> ]] || return 1

    for (( component_index = 0; component_index < component_count; component_index++ )); do
        component_name=$(manifest_value "components.$component_index.name" 2>/dev/null) || continue
        [[ "$component_name" == "$expected_name" ]] || continue
        component_value=$(manifest_value "components.$component_index.version" 2>/dev/null) || return 1
        [[ -n "$component_value" ]] || return 1
        print -r -- "$component_value"
        return 0
    done
    return 1
}

component_occurrence_count() {
    local expected_name=$1
    local component_count
    local component_index
    local component_name
    local -i matches=0

    component_count=$(manifest_value components 2>/dev/null) || return 1
    [[ "$component_count" == <-> ]] || return 1
    for (( component_index = 0; component_index < component_count; component_index++ )); do
        component_name=$(manifest_value "components.$component_index.name" 2>/dev/null) || continue
        [[ "$component_name" == "$expected_name" ]] && matches=$((matches + 1))
    done
    print -r -- "$matches"
}

patch_sha256() {
    local expected_file=$1
    local patch_count
    local patch_index
    local patch_file

    patch_count=$(manifest_value appliedPatches 2>/dev/null) || return 1
    [[ "$patch_count" == <-> ]] || return 1
    for (( patch_index = 0; patch_index < patch_count; patch_index++ )); do
        patch_file=$(manifest_value "appliedPatches.$patch_index.file" 2>/dev/null) || continue
        [[ "$patch_file" == "$expected_file" ]] || continue
        manifest_value "appliedPatches.$patch_index.sha256"
        return
    done
    return 1
}

validate_manifest() {
    local manifest="$runtime_root/share/secunda/runtime-provenance.json"
    local component
    local component_index
    local occurrence_count
    local version
    local -a expected_components
    local -a expected_versions
    local patch_index
    local patch_sha
    local -a required_patches
    local -a required_patch_hashes

    if ! is_private_metadata_file "$manifest" "$runtime_root"; then
        record_failure "source-runtime provenance manifest is missing, linked, or external"
        return
    fi
    if ! /usr/bin/awk '
        {
            for (char_index = 1; char_index <= length($0); char_index++) {
                character = substr($0, char_index, 1)
                if (character !~ /[[:space:]]/) {
                    found = 1
                    is_json = (character == "{")
                    exit
                }
            }
        }
        END { exit(found && is_json ? 0 : 1) }
    ' "$manifest"; then
        record_failure "source-runtime provenance manifest is not JSON"
        return
    fi
    if ! /usr/bin/plutil -convert xml1 -o /dev/null "$manifest" 2>/dev/null; then
        record_failure "source-runtime provenance manifest is not valid JSON"
        return
    fi

    [[ "$(manifest_value formatVersion)" == "1" ]] \
        || record_failure "runtime provenance formatVersion must be 1"
    [[ "$(manifest_value runtimeKind)" == "secunda-source-runtime" ]] \
        || record_failure "runtime provenance kind is not source-only"
    [[ "$(manifest_value architecture)" == "x86_64" ]] \
        || record_failure "runtime provenance architecture is not x86_64"

    expected_components=(Wine DXMT FreeType GMP Nettle GnuTLS)
    expected_versions=(11.0 0.80 2.13.3 6.3.0 3.10 3.8.3)
    for (( component_index = 1; component_index <= ${#expected_components}; component_index++ )); do
        component=${expected_components[$component_index]}
        version=$(component_version "$component" 2>/dev/null) || {
            record_failure "runtime provenance is missing versioned component: $component"
            continue
        }
        occurrence_count=$(component_occurrence_count "$component" 2>/dev/null) || true
        if [[ "$occurrence_count" != "1" ]]; then
            record_failure "runtime provenance component is missing or duplicated: $component"
        elif [[ "$version" != "${expected_versions[$component_index]}" ]]; then
            record_failure "runtime provenance has an unsupported version for: $component"
        else
            record_pass "runtime provenance pins expected component: $component $version"
        fi
    done

    required_patches=(
        "patches/wine-clang-syscall-abi.patch"
        "patches/wine-secunda-cef-in-process-gpu.patch"
    )
    required_patch_hashes=(
        "e624c28638055f0c1179cfb49d3b78fe0604fcf93cee97b28a5f4722e4db5364"
        "6364ef9ca1c173e55043232c98ad1d85601477ae3c89e26068cff565fd14204c"
    )
    for (( patch_index = 1; patch_index <= ${#required_patches}; patch_index++ )); do
        patch_sha=$(patch_sha256 "${required_patches[$patch_index]}" 2>/dev/null) || true
        if [[ "$patch_sha" == "${required_patch_hashes[$patch_index]}" ]]; then
            record_pass "runtime provenance pins required Wine readiness patch $patch_index"
        else
            record_failure "runtime provenance lacks required Wine readiness patch $patch_index"
        fi
    done
}

validate_dxmt_version() {
    local marker="$runtime_root/lib/wine/.secunda-dxmt-version"
    local marker_version=""
    local manifest_version=""

    if ! is_private_metadata_file "$marker" "$runtime_root"; then
        record_failure "DXMT version marker is missing, linked, or external"
        return
    fi
    IFS= read -r marker_version < "$marker" || true
    manifest_version=$(component_version DXMT 2>/dev/null) || true

    [[ "$marker_version" == "$EXPECTED_DXMT_VERSION" ]] \
        || record_failure "DXMT marker must be $EXPECTED_DXMT_VERSION"
    [[ "$manifest_version" == "$EXPECTED_DXMT_VERSION" ]] \
        || record_failure "DXMT provenance version must be $EXPECTED_DXMT_VERSION"
    [[ "$marker_version" == "$manifest_version" ]] \
        || record_failure "DXMT marker and provenance versions disagree"

    if [[ "$marker_version" == "$EXPECTED_DXMT_VERSION" \
        && "$manifest_version" == "$EXPECTED_DXMT_VERSION" ]]; then
        record_pass "DXMT $EXPECTED_DXMT_VERSION identity and placement agree"
    fi
}

scan_forbidden_references() {
    local scan_file
    local rule_index
    local relative_path
    local forbidden_payload=""
    local -i failures_before_scan=$failure_count
    local -a scan_files
    local -a rule_names
    local -a rule_patterns

    rule_names=(
        "CrossOver application path"
        "CrossOver SharedSupport path"
        "CrossOver bundle identity"
        "CrossOver bottle storage"
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
        '(^|[/\\[:space:]"=])apple_gptk([/\\[:space:]"=]|$)'
        'Game[[:space:]]*Porting[[:space:]]*Toolkit'
        'libd3dshared\.dylib'
        '(D3DMetal\.framework|libD3DMetal\.dylib)'
    )

    forbidden_payload=$(/usr/bin/find "$runtime_root" \( \
        -iname 'steam.exe' -o \
        -iname 'skyrimse.exe' -o \
        -iname 'loginusers.vdf' -o \
        -iname '*d3dmetal*' -o \
        -iname '*d3dshared*' -o \
        -iname '*apple_gptk*' -o \
        -iname 'CrossOver.app' \
    \) -print -quit 2>/dev/null)
    if [[ -n "$forbidden_payload" ]]; then
        record_failure "runtime package contains a forbidden proprietary or user payload"
    fi

    while IFS= read -r -d '' scan_file; do
        if ! is_contained "$scan_file" "$runtime_root"; then
            relative_path=${scan_file#"$runtime_root"/}
            record_failure "runtime symlink escapes package root: $relative_path"
        fi
    done < <(/usr/bin/find "$runtime_root" -type l -print0 2>/dev/null)

    scan_files=(
        "$runtime_root/bin/wine"
        "$runtime_root/bin/wine64"
        "$runtime_root/bin/wineserver"
        "$runtime_root/lib/wine/x86_64-unix/winemetal.so"
        "$runtime_root/lib/wine/x86_64-unix/winecoreaudio.so"
        "$runtime_root/lib/wine/x86_64-windows/d3d11.dll"
        "$runtime_root/lib/wine/x86_64-windows/dxgi.dll"
        "$runtime_root/lib/wine/x86_64-windows/x3daudio1_7.dll"
        "$runtime_root/lib/wine/x86_64-windows/xaudio2_7.dll"
        "$runtime_root/lib/wine/x86_64-windows/tasklist.exe"
        "$runtime_root/share/secunda/runtime-provenance.json"
        "$prefix_root/system.reg"
        "$prefix_root/user.reg"
        "$prefix_root/userdef.reg"
    )

    for scan_file in "${scan_files[@]}"; do
        [[ -f "$scan_file" ]] || continue
        if [[ "$scan_file" == "$prefix_root"/* ]] \
            && ! is_private_metadata_file "$scan_file" "$prefix_root"; then
            record_failure "selected prefix metadata is linked or external"
            continue
        fi
        for (( rule_index = 1; rule_index <= ${#rule_names}; rule_index++ )); do
            if LC_ALL=C /usr/bin/grep -a -E -i -q -- \
                "${rule_patterns[$rule_index]}" "$scan_file" 2>/dev/null; then
                record_failure "forbidden reference (${rule_names[$rule_index]}) in selected readiness metadata"
            fi
        done
    done

    if (( failure_count == failures_before_scan )); then
        record_pass "selected runtime and prefix metadata contain no forbidden runtime references"
    fi
}

validate_optional_integrity() {
    setopt local_options glob_dots

    local integrity_manifest="$runtime_root/share/secunda/runtime-files.sha256"
    local line
    local expected_hash
    local actual_hash
    local relative_path
    local target
    local runtime_file
    local -i entry_count=0
    local -i integrity_failures=0
    local -a manifest_targets
    local -a runtime_files

    if [[ ! -e "$integrity_manifest" && ! -L "$integrity_manifest" ]]; then
        record_warning "runtime integrity manifest is absent; component presence is not package integrity"
        return
    fi
    if ! is_private_metadata_file "$integrity_manifest" "$runtime_root"; then
        record_failure "runtime integrity manifest is linked or external"
        return
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        entry_count=$((entry_count + 1))
        if [[ ! "$line" =~ '^[0-9a-fA-F]{64} [ *]\./[^[:cntrl:]]+$' ]]; then
            integrity_failures=$((integrity_failures + 1))
            continue
        fi

        expected_hash=${line[1,64]:l}
        relative_path=${line[67,-1]}
        if [[ "$relative_path" == /* || "/${relative_path#./}/" == */../* ]]; then
            integrity_failures=$((integrity_failures + 1))
            continue
        fi

        target="$runtime_root/${relative_path#./}"
        if [[ ! -f "$target" || -L "$target" || "$target" == "$integrity_manifest" ]] \
            || ! is_contained "$target" "$runtime_root"; then
            integrity_failures=$((integrity_failures + 1))
            continue
        fi
        if (( ${manifest_targets[(Ie)$target]} > 0 )); then
            integrity_failures=$((integrity_failures + 1))
            continue
        fi
        manifest_targets+=("$target")

        actual_hash=$(/usr/bin/shasum -a 256 "$target" 2>/dev/null \
            | /usr/bin/awk '{print tolower($1)}')
        [[ "$actual_hash" == "$expected_hash" ]] \
            || integrity_failures=$((integrity_failures + 1))
    done < "$integrity_manifest"

    runtime_files=()
    for runtime_file in "$runtime_root"/**/*(.N); do
        [[ "$runtime_file" == "$integrity_manifest" ]] && continue
        runtime_files+=("$runtime_file")
        (( ${manifest_targets[(Ie)$runtime_file]} > 0 )) \
            || integrity_failures=$((integrity_failures + 1))
    done
    (( ${#manifest_targets[@]} == ${#runtime_files[@]} )) \
        || integrity_failures=$((integrity_failures + 1))

    if (( entry_count == 0 || integrity_failures > 0 )); then
        record_failure "runtime integrity manifest does not verify"
    else
        record_pass "runtime integrity manifest verifies"
    fi
}
