#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
APP_ROOT=${1:-"$REPOSITORY_ROOT/dist/Secunda Launcher.app"}
CONTENTS="$APP_ROOT/Contents"
LAUNCHER="$CONTENTS/MacOS/SecundaLauncher"
RUNTIME_ROOT="$CONTENTS/Resources/runtime"

if [[ ! -x "$LAUNCHER" || ! -x "$RUNTIME_ROOT/bin/wine" ]]; then
    echo "Packaged app is missing its launcher or source runtime." >&2
    exit 1
fi

if [[ $(file -b "$LAUNCHER") != *arm64* ]]; then
    echo "Secunda launcher is not native arm64 code." >&2
    exit 1
fi

while IFS= read -r launcher_rpath; do
    case "$launcher_rpath" in
        @*|/usr/lib/*) ;;
        *)
            echo "Launcher contains a non-system RPATH: $launcher_rpath" >&2
            exit 1
            ;;
    esac
done < <(otool -l "$LAUNCHER" | awk '
    /cmd LC_RPATH/ { awaiting_path = 1; next }
    awaiting_path && /path / { print $2; awaiting_path = 0 }
')

while IFS= read -r dependency; do
    case "$dependency" in
        @*|/usr/lib/*|/System/Library/*) ;;
        *)
            echo "Launcher contains a non-system dependency: $dependency" >&2
            exit 1
            ;;
    esac
done < <(otool -L "$LAUNCHER" | tail -n +2 | awk '{print $1}')

deployment_target=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$CONTENTS/Info.plist")
launcher_minimum_os=$(vtool -show-build "$LAUNCHER" 2>/dev/null | awk '/minos/{print $2; exit}')
if [[ -z "$launcher_minimum_os" ]]; then
    echo "Secunda launcher is missing its macOS deployment target." >&2
    exit 1
fi
if awk -v actual="$launcher_minimum_os" -v maximum="$deployment_target" 'BEGIN {
    split(actual, a, "."); split(maximum, m, ".");
    if ((a[1] + 0) > (m[1] + 0)) exit 0;
    if ((a[1] + 0) < (m[1] + 0)) exit 1;
    exit ((a[2] + 0) > (m[2] + 0)) ? 0 : 1;
}'; then
    echo "Secunda launcher requires macOS $launcher_minimum_os, above its declared $deployment_target floor." >&2
    exit 1
fi
SECUNDA_DEPLOYMENT_TARGET="$deployment_target" \
    "$SCRIPT_DIR/verify-runtime-distribution.sh" "$RUNTIME_ROOT"

"$SCRIPT_DIR/verify-runtime-payload.sh" "$APP_ROOT"

signed_runtime_count=0
outer_team_identifier=$(codesign -dv --verbose=4 "$APP_ROOT" 2>&1 |
    awk -F= '/^TeamIdentifier=/{print $2; exit}')
while IFS= read -r -d '' runtime_file; do
    file -b "$runtime_file" 2>/dev/null | grep -q 'Mach-O' || continue
    codesign --verify --strict "$runtime_file"
    if [[ -n "$outer_team_identifier" && "$outer_team_identifier" != "not set" ]]; then
        runtime_team_identifier=$(codesign -dv --verbose=4 "$runtime_file" 2>&1 |
            awk -F= '/^TeamIdentifier=/{print $2; exit}')
        if [[ "$runtime_team_identifier" != "$outer_team_identifier" ]]; then
            echo "Runtime worker is not signed by the app team: $runtime_file" >&2
            exit 1
        fi
    fi
    (( signed_runtime_count += 1 ))
done < <(find "$RUNTIME_ROOT" -type f -print0)
if (( signed_runtime_count == 0 )); then
    echo "Packaged runtime contains no signed Mach-O workers." >&2
    exit 1
fi

if [[ -n "$outer_team_identifier" && "$outer_team_identifier" != "not set" ]]; then
    for wine_worker in \
        "$RUNTIME_ROOT/bin/wine" \
        "$RUNTIME_ROOT/lib/wine/x86_64-unix/wine"; do
        if ! codesign -dv --verbose=4 "$wine_worker" 2>&1 | grep -q 'flags=.*runtime'; then
            echo "Developer-ID Wine worker is missing hardened runtime: $wine_worker" >&2
            exit 1
        fi
        executable_memory_allowed=$(codesign -d --entitlements :- "$wine_worker" 2>/dev/null |
            plutil -extract 'com\.apple\.security\.cs\.allow-unsigned-executable-memory' \
                raw -o - - 2>/dev/null || true)
        if [[ "$executable_memory_allowed" != "true" ]]; then
            echo "Developer-ID Wine worker is missing executable-memory permission: $wine_worker" >&2
            exit 1
        fi
    done
fi

codesign --verify --deep --strict "$APP_ROOT"
echo "PASS: packaged Secunda app is arm64, source-only, relocatable, and signed ($signed_runtime_count runtime workers)."
