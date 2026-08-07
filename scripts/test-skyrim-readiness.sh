#!/bin/zsh -f
set -euo pipefail

SCRIPT_DIR=${0:A:h}
VERIFIER="$SCRIPT_DIR/verify-skyrim-readiness.sh"
INTEGRITY_CREATOR="$SCRIPT_DIR/create-runtime-integrity.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/secunda-readiness-test.XXXXXX")
BASE="$TEST_ROOT/base/Secunda Launcher"
typeset -i pass_count=0

cleanup() {
    [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]] && rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

if LC_ALL=C /usr/bin/grep -E -q \
    '(/bin/ps|/usr/bin/ps|/usr/bin/pgrep|kern\.procargs|/proc/[^/]*/(cmdline|environ))' \
    "$VERIFIER" "$SCRIPT_DIR/lib/skyrim-readiness-"*.zsh; then
    print -u2 -- "FAIL: readiness audit contains a prohibited process-inspection path"
    exit 1
fi

fixture_digest() {
    local fixture=$1
    (
        cd "$fixture"
        /usr/bin/find . -print0 | LC_ALL=C sort -z \
            | while IFS= read -r -d '' fixture_entry; do
                entry_mode=$(/usr/bin/stat -f '%Lp' "$fixture_entry")
                if [[ -L "$fixture_entry" ]]; then
                    print -r -- "link\t$entry_mode\t$fixture_entry\t$(readlink "$fixture_entry")"
                elif [[ -f "$fixture_entry" ]]; then
                    entry_hash=$(/usr/bin/shasum -a 256 "$fixture_entry" | /usr/bin/awk '{print $1}')
                    print -r -- "file\t$entry_mode\t$fixture_entry\t$entry_hash"
                elif [[ -d "$fixture_entry" ]]; then
                    print -r -- "directory\t$entry_mode\t$fixture_entry"
                else
                    print -r -- "other\t$entry_mode\t$fixture_entry"
                fi
            done
    ) | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

refresh_integrity() {
    local runtime=$1
    "$INTEGRITY_CREATOR" "$runtime" >/dev/null
}

create_synthetic_pe() {
    local destination=$1
    local byte_count=$2

    /bin/dd if=/dev/zero of="$destination" bs="$byte_count" count=1 status=none
    /usr/bin/printf 'MZ' \
        | /bin/dd of="$destination" bs=1 seek=0 conv=notrunc status=none
    /usr/bin/printf '\200\000\000\000' \
        | /bin/dd of="$destination" bs=1 seek=60 conv=notrunc status=none
    /usr/bin/printf \
        'PE\000\000\144\206\001\000\000\000\000\000\000\000\000\000\000\000\000\000\360\000\042\000' \
        | /bin/dd of="$destination" bs=1 seek=128 conv=notrunc status=none
    /usr/bin/printf '\013\002' \
        | /bin/dd of="$destination" bs=1 seek=152 conv=notrunc status=none
    /usr/bin/printf '\000\002\000\000' \
        | /bin/dd of="$destination" bs=1 seek=156 conv=notrunc status=none
    /usr/bin/printf '\000\020\000\000' \
        | /bin/dd of="$destination" bs=1 seek=168 conv=notrunc status=none
    /usr/bin/printf '\000\020\000\000' \
        | /bin/dd of="$destination" bs=1 seek=172 conv=notrunc status=none
    /usr/bin/printf '\000\020\000\000\000\000\000\000' \
        | /bin/dd of="$destination" bs=1 seek=176 conv=notrunc status=none
    /usr/bin/printf '\000\020\000\000' \
        | /bin/dd of="$destination" bs=1 seek=184 conv=notrunc status=none
    /usr/bin/printf '\000\002\000\000' \
        | /bin/dd of="$destination" bs=1 seek=188 conv=notrunc status=none
    /usr/bin/printf '\000\040\000\000' \
        | /bin/dd of="$destination" bs=1 seek=208 conv=notrunc status=none
    /usr/bin/printf '\000\002\000\000' \
        | /bin/dd of="$destination" bs=1 seek=212 conv=notrunc status=none
    /usr/bin/printf '\020\000\000\000' \
        | /bin/dd of="$destination" bs=1 seek=260 conv=notrunc status=none
    /usr/bin/printf '.text\000\000\000\000\001\000\000\000\020\000\000\000\002\000\000\000\002\000\000' \
        | /bin/dd of="$destination" bs=1 seek=392 conv=notrunc status=none
    /usr/bin/printf '\040\000\000\140' \
        | /bin/dd of="$destination" bs=1 seek=428 conv=notrunc status=none
    /usr/bin/printf '\303' \
        | /bin/dd of="$destination" bs=1 seek=512 conv=notrunc status=none
}

create_skyrim_master() {
    local destination=$1

    /bin/dd if=/dev/zero of="$destination" bs=1048576 count=1 status=none
    /usr/bin/printf 'TES4' \
        | /bin/dd of="$destination" bs=1 seek=0 conv=notrunc status=none
    /usr/bin/printf '\022\000\000\000' \
        | /bin/dd of="$destination" bs=1 seek=4 conv=notrunc status=none
    /usr/bin/printf 'HEDR\014\000' \
        | /bin/dd of="$destination" bs=1 seek=24 conv=notrunc status=none
}

create_skyrim_save() {
    local destination=$1

    /bin/dd if=/dev/zero of="$destination" bs=4096 count=1 status=none
    /usr/bin/printf 'TESV_SAVEGAME' \
        | /bin/dd of="$destination" bs=1 seek=0 conv=notrunc status=none
    /usr/bin/printf '\100\000\000\000' \
        | /bin/dd of="$destination" bs=1 seek=13 conv=notrunc status=none
}

write_runtime_tripwire() {
    local destination=$1

    print -r -- '#!/bin/zsh -f
runtime_probe_root=${0:A:h}
while [[ "$runtime_probe_root" != "/" \
    && ! -f "$runtime_probe_root/share/secunda/runtime-provenance.json" ]]; do
    runtime_probe_root=$runtime_probe_root:h
done
print -r -- "PROHIBITED: readiness audit executed a runtime worker" \
    > "$runtime_probe_root/PROHIBITED_RUNTIME_EXECUTION"
exit 97
' > "$destination"
}

run_verifier() {
    local fixture=$1
    "$VERIFIER" \
        --runtime "$fixture/runtime" \
        --prefix "$fixture/Bottles/Ready" \
        --bottles-root "$fixture/Bottles"
}

expect_pass() {
    local name=$1
    local fixture=$2
    local before
    local after

    before=$(fixture_digest "$fixture")
    if ! run_verifier "$fixture" > "$TEST_ROOT/last.stdout" 2> "$TEST_ROOT/last.stderr"; then
        print -u2 -- "FAIL: expected success: $name"
        cat "$TEST_ROOT/last.stderr" >&2
        exit 1
    fi
    after=$(fixture_digest "$fixture")
    if [[ "$before" != "$after" ]]; then
        print -u2 -- "FAIL: verifier modified its fixture: $name"
        exit 1
    fi
    if LC_ALL=C grep -Fq 'fixture-account-secret' \
        "$TEST_ROOT/last.stdout" "$TEST_ROOT/last.stderr"; then
        print -u2 -- "FAIL: verifier exposed credential-shaped fixture text: $name"
        exit 1
    fi

    pass_count=$((pass_count + 1))
    print -- "PASS: $name"
}

expect_fail() {
    local name=$1
    local fixture=$2
    local expected_message=$3
    local before
    local after

    before=$(fixture_digest "$fixture")
    if run_verifier "$fixture" > "$TEST_ROOT/last.stdout" 2> "$TEST_ROOT/last.stderr"; then
        print -u2 -- "FAIL: expected rejection: $name"
        cat "$TEST_ROOT/last.stdout" >&2
        exit 1
    fi
    if ! LC_ALL=C grep -Fq -- "$expected_message" "$TEST_ROOT/last.stderr"; then
        print -u2 -- "FAIL: missing expected rejection for: $name"
        cat "$TEST_ROOT/last.stderr" >&2
        exit 1
    fi
    after=$(fixture_digest "$fixture")
    if [[ "$before" != "$after" ]]; then
        print -u2 -- "FAIL: verifier modified rejected fixture: $name"
        exit 1
    fi
    if LC_ALL=C grep -Fq 'fixture-account-secret' \
        "$TEST_ROOT/last.stdout" "$TEST_ROOT/last.stderr"; then
        print -u2 -- "FAIL: rejection exposed credential-shaped fixture text: $name"
        exit 1
    fi

    pass_count=$((pass_count + 1))
    print -- "PASS: $name"
}

expect_pass_message() {
    local name=$1
    local fixture=$2
    local expected_message=$3

    expect_pass "$name" "$fixture"
    if ! LC_ALL=C grep -Fq -- "$expected_message" \
        "$TEST_ROOT/last.stdout" "$TEST_ROOT/last.stderr"; then
        print -u2 -- "FAIL: missing expected success evidence for: $name"
        cat "$TEST_ROOT/last.stdout" >&2
        cat "$TEST_ROOT/last.stderr" >&2
        exit 1
    fi
}

expect_direct_fail() {
    local name=$1
    local fixture=$2
    local expected_message=$3
    local runtime=$4
    local prefix=$5
    local bottles=$6
    local verifier=${7:-$VERIFIER}
    local before
    local after

    before=$(fixture_digest "$fixture")
    if "$verifier" \
        --runtime "$runtime" \
        --prefix "$prefix" \
        --bottles-root "$bottles" \
        > "$TEST_ROOT/last.stdout" 2> "$TEST_ROOT/last.stderr"; then
        print -u2 -- "FAIL: expected rejection: $name"
        exit 1
    fi
    after=$(fixture_digest "$fixture")
    if [[ "$before" != "$after" ]]; then
        print -u2 -- "FAIL: verifier modified rejected fixture: $name"
        exit 1
    fi
    if ! LC_ALL=C grep -Fq -- "$expected_message" "$TEST_ROOT/last.stderr"; then
        print -u2 -- "FAIL: missing expected rejection for: $name"
        cat "$TEST_ROOT/last.stderr" >&2
        exit 1
    fi
    if LC_ALL=C grep -Fq 'fixture-account-secret' \
        "$TEST_ROOT/last.stdout" "$TEST_ROOT/last.stderr"; then
        print -u2 -- "FAIL: rejection exposed credential-shaped fixture text: $name"
        exit 1
    fi

    pass_count=$((pass_count + 1))
    print -- "PASS: $name"
}

make_case() {
    local name=$1
    local case_container="$TEST_ROOT/$name"
    local destination="$case_container/Secunda Launcher"

    mkdir -p "$case_container"
    cp -R "$BASE" "$destination"
    print -r -- "$destination"
}

mkdir -p \
    "$BASE/runtime/bin" \
    "$BASE/runtime/lib/wine/x86_64-unix" \
    "$BASE/runtime/lib/wine/x86_64-windows" \
    "$BASE/runtime/share/secunda" \
    "$BASE/Bottles/Ready/drive_c/users/secunda/Documents/My Games/Skyrim Special Edition/Saves" \
    "$BASE/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition/Data"

typeset -a fixture_runtime_files
fixture_runtime_files=(
    "lib/libfreetype.6.dylib"
    "lib/libgnutls.30.dylib"
    "lib/libgmp.10.dylib"
    "lib/libnettle.8.dylib"
    "lib/libhogweed.6.dylib"
    "lib/wine/x86_64-unix/wine"
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
for relative_path in "${fixture_runtime_files[@]}"; do
    mkdir -p "$BASE/runtime/${relative_path:h}"
    print -r -- "open source fixture component" > "$BASE/runtime/$relative_path"
done

write_runtime_tripwire "$BASE/runtime/bin/wine"
write_runtime_tripwire "$BASE/runtime/bin/wineserver"
write_runtime_tripwire "$BASE/runtime/lib/wine/x86_64-unix/wine"
chmod +x \
    "$BASE/runtime/bin/wine" \
    "$BASE/runtime/bin/wineserver" \
    "$BASE/runtime/lib/wine/x86_64-unix/wine"
ln -s libfreetype.6.dylib "$BASE/runtime/lib/libfreetype-current.dylib"
print -r -- '0.80' > "$BASE/runtime/lib/wine/.secunda-dxmt-version"

cp "$SCRIPT_DIR/../packaging/runtime-provenance.json" \
    "$BASE/runtime/share/secunda/runtime-provenance.json"

print -r -- 'WINE REGISTRY Version 2' > "$BASE/Bottles/Ready/system.reg"
print -r -- 'WINE REGISTRY Version 2' > "$BASE/Bottles/Ready/userdef.reg"
print -r -- 'WINE REGISTRY Version 2

[Software\\Valve\\Steam] 1
"AutoLoginUser"="fixture-account-secret"

[Software\\Wine\\DllOverrides] 1
"x3daudio1_6"="builtin"
"x3daudio1_7"="builtin"
"xaudio2_6"="builtin"
"xaudio2_7"="builtin"
' > "$BASE/Bottles/Ready/user.reg"

create_synthetic_pe \
    "$BASE/Bottles/Ready/drive_c/Program Files (x86)/Steam/steam.exe" \
    102400
print -r -- '"AppState"
{
    "appid" "489830"
    "StateFlags" "4"
    "BytesDownloaded" "100"
    "BytesToDownload" "100"
    "BytesStaged" "25"
    "BytesToStage" "25"
    "LastOwner" "fixture-account-secret"
    "installdir" "Skyrim Special Edition"
}' > "$BASE/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/appmanifest_489830.acf"
create_synthetic_pe \
    "$BASE/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition/SkyrimSE.exe" \
    1048576
create_skyrim_master \
    "$BASE/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition/Data/Skyrim.esm"
create_skyrim_save \
    "$BASE/Bottles/Ready/drive_c/users/secunda/Documents/My Games/Skyrim Special Edition/Saves/test.ess"

refresh_integrity "$BASE/runtime"
expect_pass "complete fixture is accepted without mutation or credential output" "$BASE"
if [[ -e "$BASE/runtime/PROHIBITED_RUNTIME_EXECUTION" ]]; then
    print -u2 -- "FAIL: readiness verifier executed a runtime worker"
    exit 1
fi

case_root=$(make_case missing-integrity-metadata)
rm -f "$case_root/runtime/share/secunda/runtime-links.tsv"
expect_fail \
    "missing exact runtime integrity metadata is rejected" \
    "$case_root" \
    "runtime exact integrity metadata is missing, linked, or external"

case_root=$(make_case uncovered-runtime-file)
print -r -- 'uncovered runtime payload' > "$case_root/runtime/lib/uncovered.bin"
expect_fail \
    "runtime file absent from the exact inventory is rejected" \
    "$case_root" \
    "runtime exact integrity inventories do not verify"

case_root=$(make_case stale-runtime-mode)
chmod 0600 "$case_root/runtime/lib/libfreetype.6.dylib"
expect_fail \
    "runtime handoff mode drift is rejected" \
    "$case_root" \
    "runtime exact integrity inventories do not verify"

case_root=$(make_case stale-runtime-bytes)
print -r -- 'tracked byte drift' >> "$case_root/runtime/lib/libfreetype.6.dylib"
expect_fail \
    "tracked runtime file byte drift is rejected" \
    "$case_root" \
    "runtime exact integrity inventories do not verify"

case_root=$(make_case added-runtime-link)
ln -s libgnutls.30.dylib "$case_root/runtime/lib/added-library-link.dylib"
expect_fail \
    "runtime symlink absent from the exact inventory is rejected" \
    "$case_root" \
    "runtime exact integrity inventories do not verify"

case_root=$(make_case retargeted-runtime-link)
rm -f "$case_root/runtime/lib/libfreetype-current.dylib"
ln -s libgnutls.30.dylib "$case_root/runtime/lib/libfreetype-current.dylib"
expect_fail \
    "runtime symlink target drift is rejected" \
    "$case_root" \
    "runtime exact integrity inventories do not verify"

case_root=$(make_case provenance-drift)
print >> "$case_root/runtime/share/secunda/runtime-provenance.json"
refresh_integrity "$case_root/runtime"
expect_fail \
    "valid JSON provenance that differs from the pinned canonical bytes is rejected" \
    "$case_root" \
    "runtime provenance does not match the pinned canonical source manifest"

case_root=$(make_case xml-provenance)
/usr/bin/plutil -convert xml1 \
    "$case_root/runtime/share/secunda/runtime-provenance.json"
refresh_integrity "$case_root/runtime"
expect_fail \
    "property-list provenance is rejected even when plutil can parse it" \
    "$case_root" \
    "source-runtime provenance manifest is not JSON"

case_root=$(make_case wrong-patch-provenance)
/usr/bin/sed -i '' \
    's/e624c28638055f0c1179cfb49d3b78fe0604fcf93cee97b28a5f4722e4db5364/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
    "$case_root/runtime/share/secunda/runtime-provenance.json"
refresh_integrity "$case_root/runtime"
expect_fail \
    "runtime provenance with a different readiness patch is rejected" \
    "$case_root" \
    "runtime provenance lacks required Wine readiness patch 1"

case_root=$(make_case provenance-parent-symlink)
mv "$case_root/runtime/share/secunda" "$case_root/runtime/share/metadata"
ln -s metadata "$case_root/runtime/share/secunda"
expect_fail \
    "provenance beneath a symbolic-link metadata directory is rejected" \
    "$case_root" \
    "source-runtime provenance manifest is missing, linked, or external"

case_root=$(make_case missing-audio)
rm -f "$case_root/runtime/lib/wine/x86_64-windows/x3daudio1_7.dll"
refresh_integrity "$case_root/runtime"
expect_fail \
    "missing X3DAudio runtime is rejected" \
    "$case_root" \
    "missing runtime component: lib/wine/x86_64-windows/x3daudio1_7.dll"

case_root=$(make_case missing-override)
/usr/bin/sed -i '' '/"xaudio2_7"="builtin"/d' "$case_root/Bottles/Ready/user.reg"
expect_fail \
    "missing XAudio builtin override is rejected" \
    "$case_root" \
    "Wine builtin override is missing or not builtin: xaudio2_7"

case_root=$(make_case linked-prefix-metadata)
mkdir -p "$case_root/Bottles/Ready/metadata"
mv "$case_root/Bottles/Ready/user.reg" "$case_root/Bottles/Ready/metadata/user.reg"
ln -s metadata/user.reg "$case_root/Bottles/Ready/user.reg"
expect_fail \
    "symbolic-link prefix metadata is rejected" \
    "$case_root" \
    "prefix user.reg is missing, linked, or external"

case_root=$(make_case save-symlink)
outside_saves="$case_root/outside-saves"
mkdir -p "$outside_saves"
rm -rf -- "$case_root/Bottles/Ready/drive_c/users/secunda/Documents/My Games/Skyrim Special Edition/Saves"
ln -s "$outside_saves" \
    "$case_root/Bottles/Ready/drive_c/users/secunda/Documents/My Games/Skyrim Special Edition/Saves"
expect_fail \
    "nested save symlink is rejected" \
    "$case_root" \
    "Skyrim profile contains a symbolic link"

case_root=$(make_case wrong-app)
/usr/bin/sed -i '' 's/"appid" "489830"/"appid" "123"/' \
    "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/appmanifest_489830.acf"
expect_fail \
    "wrong Steam app manifest is rejected" \
    "$case_root" \
    "Skyrim app manifest does not identify app 489830"

case_root=$(make_case incomplete-app-state)
/usr/bin/sed -i '' 's/"StateFlags" "4"/"StateFlags" "1026"/' \
    "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/appmanifest_489830.acf"
expect_fail \
    "incomplete Steam AppState is rejected" \
    "$case_root" \
    "Skyrim app manifest does not report a complete installed state"

case_root=$(make_case fake-steam-payload)
print -r -- 'MZ but not a packaged Windows executable' \
    > "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steam.exe"
expect_fail \
    "fake Steam executable is rejected" \
    "$case_root" \
    "Steam executable is not a plausible packaged Windows payload"

case_root=$(make_case fake-skyrim-payload)
print -r -- 'MZ but not a packaged Windows executable' \
    > "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition/SkyrimSE.exe"
expect_fail \
    "fake Skyrim executable is rejected" \
    "$case_root" \
    "Skyrim executable is not a plausible packaged Windows payload"

case_root=$(make_case header-only-skyrim-payload)
/usr/bin/printf '\000\000' \
    | /bin/dd \
        of="$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition/SkyrimSE.exe" \
        bs=1 seek=134 conv=notrunc status=none
expect_fail \
    "large PE-shaped Skyrim payload without a coherent section table is rejected" \
    "$case_root" \
    "Skyrim executable is not a plausible packaged Windows payload"

case_root=$(make_case missing-master-data)
rm -f "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition/Data/Skyrim.esm"
expect_fail \
    "missing Skyrim baseline data is rejected" \
    "$case_root" \
    "Skyrim baseline data payload is missing or external"

case_root=$(make_case tiny-master-data)
print -r -- 'TES4' \
    > "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition/Data/Skyrim.esm"
expect_fail \
    "implausibly small Skyrim baseline data is rejected" \
    "$case_root" \
    "Skyrim baseline data payload is implausibly small"

case_root=$(make_case header-only-master-data)
/bin/dd if=/dev/zero \
    of="$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition/Data/Skyrim.esm" \
    bs=1048576 count=1 status=none
/usr/bin/printf 'TES4' \
    | /bin/dd \
        of="$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition/Data/Skyrim.esm" \
        bs=1 seek=0 conv=notrunc status=none
expect_fail \
    "large TES4-shaped master file without a coherent first record is rejected" \
    "$case_root" \
    "Skyrim baseline data does not have a plausible TES4 record structure"

case_root=$(make_case empty-save)
print -n -- '' \
    > "$case_root/Bottles/Ready/drive_c/users/secunda/Documents/My Games/Skyrim Special Edition/Saves/test.ess"
expect_pass_message \
    "empty save is not misreported as verified persistence" \
    "$case_root" \
    "Skyrim save directory has .ess files, but none has a plausible non-empty save structure"

case_root=$(make_case empty-save-directory)
rm -f \
    "$case_root/Bottles/Ready/drive_c/users/secunda/Documents/My Games/Skyrim Special Edition/Saves/test.ess"
expect_pass_message \
    "empty save directory remains unverified instead of receiving a persistence pass" \
    "$case_root" \
    "Skyrim save directory has no regular .ess save; persistence was not proven"

case_root=$(make_case malformed-save)
/bin/dd if=/dev/zero \
    of="$case_root/Bottles/Ready/drive_c/users/secunda/Documents/My Games/Skyrim Special Edition/Saves/test.ess" \
    bs=4096 count=1 status=none
/usr/bin/printf 'TESV_SAVEGAME' \
    | /bin/dd \
        of="$case_root/Bottles/Ready/drive_c/users/secunda/Documents/My Games/Skyrim Special Edition/Saves/test.ess" \
        bs=1 seek=0 conv=notrunc status=none
expect_pass_message \
    "signature-shaped save with a zero declared header is not misreported as verified" \
    "$case_root" \
    "Skyrim save directory has .ess files, but none has a plausible non-empty save structure"

host_user=$(/usr/bin/id -un)
if [[ "$host_user" != "steamuser" && "$host_user" != "secunda" ]]; then
    case_root=$(make_case launcher-windows-user)
    users_root="$case_root/Bottles/Ready/drive_c/users"
    mkdir -p "$users_root/$host_user"
    cp -R "$users_root/secunda/Documents" "$users_root/$host_user/Documents"
    mv "$users_root/secunda/Documents" "$users_root/secunda/Documents.unselected"
    mkdir -p "$case_root/outside-documents"
    ln -s "$case_root/outside-documents" "$users_root/secunda/Documents"
    expect_pass \
        "Windows-user selection matches the launcher's host-user priority" \
        "$case_root"
fi

case_root=$(make_case contained-custom-library)
custom_library="$case_root/Bottles/Ready/drive_c/SecondaryLibrary"
mkdir -p "$custom_library/steamapps/common"
mv "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/appmanifest_489830.acf" \
    "$custom_library/steamapps/appmanifest_489830.acf"
mv "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition" \
    "$custom_library/steamapps/common/Skyrim Special Edition"
print -r -- '"libraryfolders"
{
    "0"
    {
        "path" "C:\\SecondaryLibrary"
    }
}' > "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/libraryfolders.vdf"
expect_pass \
    "prefix-contained custom Steam library is accepted" \
    "$case_root"

case_root=$(make_case escaping-custom-library)
outside_library="$case_root/outside-library"
mkdir -p "$outside_library/steamapps/common" "$case_root/Bottles/Ready/dosdevices"
mv "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/appmanifest_489830.acf" \
    "$outside_library/steamapps/appmanifest_489830.acf"
mv "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition" \
    "$outside_library/steamapps/common/Skyrim Special Edition"
ln -s "$case_root" "$case_root/Bottles/Ready/dosdevices/d:"
print -r -- '"libraryfolders"
{
    "0"
    {
        "path" "D:\\outside-library"
    }
}' > "$case_root/Bottles/Ready/drive_c/Program Files (x86)/Steam/steamapps/libraryfolders.vdf"
expect_fail \
    "custom Steam library resolving outside the prefix is ignored" \
    "$case_root" \
    "Steam app manifest for Skyrim is absent from launcher-resolved, prefix-contained libraries"

case_root=$(make_case forbidden-runtime)
print -r -- '/Applications/CrossOver.app/Contents/SharedSupport/CrossOver' \
    >> "$case_root/runtime/bin/wine"
refresh_integrity "$case_root/runtime"
expect_fail \
    "forbidden runtime identity is rejected without echoing evidence" \
    "$case_root" \
    "forbidden reference (CrossOver application path)"

case_root=$(make_case escaping-integrity)
print -r -- 'fixture-account-secret' > "$case_root/credential-source"
escape_hash=$(/usr/bin/shasum -a 256 "$case_root/credential-source" | /usr/bin/awk '{print $1}')
print -r -- "$escape_hash  ./../credential-source" \
    > "$case_root/runtime/share/secunda/runtime-files.sha256"
expect_fail \
    "integrity manifest cannot read outside the runtime" \
    "$case_root" \
    "runtime exact integrity inventories do not verify"

case_root=$(make_case symlink-prefix)
ln -s "$case_root/Bottles/Ready" "$case_root/Bottles/Alias"
expect_direct_fail \
    "symlink managed prefix is rejected without mutation" \
    "$case_root" \
    "runtime, prefix, and bottles roots must not be symbolic links" \
    "$case_root/runtime" \
    "$case_root/Bottles/Alias" \
    "$case_root/Bottles"

case_root=$(make_case missing-validation-library)
copied_verifier_root="$case_root/copied-verifier"
mkdir -p "$copied_verifier_root/scripts"
cp "$VERIFIER" "$copied_verifier_root/scripts/verify-skyrim-readiness.sh"
chmod +x "$copied_verifier_root/scripts/verify-skyrim-readiness.sh"
expect_direct_fail \
    "missing readiness validation library fails closed" \
    "$case_root" \
    "readiness validation library is missing or linked" \
    "$case_root/runtime" \
    "$case_root/Bottles/Ready" \
    "$case_root/Bottles" \
    "$copied_verifier_root/scripts/verify-skyrim-readiness.sh"

case_root=$(make_case failing-validation-library)
copied_verifier_root="$case_root/copied-verifier"
mkdir -p "$copied_verifier_root/scripts/lib"
cp "$VERIFIER" "$copied_verifier_root/scripts/verify-skyrim-readiness.sh"
cp "$SCRIPT_DIR/lib/skyrim-readiness-runtime.zsh" \
    "$copied_verifier_root/scripts/lib/skyrim-readiness-runtime.zsh"
print -r -- 'return 91' \
    >> "$copied_verifier_root/scripts/lib/skyrim-readiness-runtime.zsh"
chmod +x "$copied_verifier_root/scripts/verify-skyrim-readiness.sh"
expect_direct_fail \
    "nonzero readiness validation library load fails closed" \
    "$case_root" \
    "readiness validation library could not be loaded" \
    "$case_root/runtime" \
    "$case_root/Bottles/Ready" \
    "$case_root/Bottles" \
    "$copied_verifier_root/scripts/verify-skyrim-readiness.sh"

case_root=$(make_case wrong-production-root)
mv "$case_root/Bottles" "$case_root/bottles"
expect_direct_fail \
    "non-Secunda bottles root is rejected without a caller bypass" \
    "$case_root" \
    "production prefix is not under Secunda Launcher/Bottles" \
    "$case_root/runtime" \
    "$case_root/bottles/Ready" \
    "$case_root/bottles"

case_root=$(make_case broad-runtime-root)
expect_direct_fail \
    "broad runtime root is rejected before scanning" \
    "$case_root" \
    "audit roots are too broad" \
    "/tmp" \
    "$case_root/Bottles/Ready" \
    "$case_root/Bottles"

case_root=$(make_case overlapping-roots)
expect_direct_fail \
    "runtime and managed bottles roots cannot overlap" \
    "$case_root" \
    "runtime and managed bottles roots must not overlap" \
    "$case_root/Bottles" \
    "$case_root/Bottles/Ready" \
    "$case_root/Bottles"

print -- "PASS: $pass_count Skyrim readiness verifier contracts verified."
