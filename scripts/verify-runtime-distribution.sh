#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
RUNTIME_ROOT=${1:-"$REPOSITORY_ROOT/Runtime/wine"}
RUNTIME_ROOT=${RUNTIME_ROOT:A}
DEPLOYMENT_TARGET=${SECUNDA_DEPLOYMENT_TARGET:-15.0}
NOTICE_ROOT="$RUNTIME_ROOT/share/secunda"

required_files=(
    "$RUNTIME_ROOT/bin/wine"
    "$RUNTIME_ROOT/bin/wineserver"
    "$RUNTIME_ROOT/bin/secunda-rosetta-debug-broker"
    "$RUNTIME_ROOT/lib/wine/x86_64-unix/winemetal.so"
    "$RUNTIME_ROOT/lib/wine/x86_64-windows/d3d11.dll"
    "$RUNTIME_ROOT/lib/wine/x86_64-windows/dxgi.dll"
    "$RUNTIME_ROOT/lib/libMoltenVK.dylib"
    "$RUNTIME_ROOT/lib/libSDL2-2.0.0.dylib"
    "$RUNTIME_ROOT/share/dxvk/x32/d3d9.dll"
    "$RUNTIME_ROOT/share/dxvk/x64/d3d9.dll"
    "$NOTICE_ROOT/runtime-provenance.json"
    "$NOTICE_ROOT/runtime-sbom.spdx.json"
    "$NOTICE_ROOT/THIRD_PARTY_NOTICES.txt"
    "$NOTICE_ROOT/runtime-files.sha256"
    "$NOTICE_ROOT/runtime-links.tsv"
    "$NOTICE_ROOT/runtime-modes.tsv"
    "$NOTICE_ROOT/dependencies.complete"
    "$NOTICE_ROOT/licenses/Wine-LGPL-2.1-or-later.txt"
    "$NOTICE_ROOT/licenses/DXMT-MIT.txt"
    "$NOTICE_ROOT/licenses/DXVK-Zlib.txt"
    "$NOTICE_ROOT/licenses/MoltenVK-Apache-2.0.txt"
    "$NOTICE_ROOT/licenses/SDL2-Zlib.txt"
    "$NOTICE_ROOT/licenses/FreeType-FTL.txt"
    "$NOTICE_ROOT/licenses/GMP-LGPL-3.0-or-later.txt"
    "$NOTICE_ROOT/licenses/GMP-GPL-3.0.txt"
    "$NOTICE_ROOT/licenses/Nettle-LGPL-3.0-or-later.txt"
    "$NOTICE_ROOT/licenses/Nettle-GPL-3.0.txt"
    "$NOTICE_ROOT/licenses/GnuTLS-LGPL-2.1-or-later.txt"
    "$NOTICE_ROOT/licenses/libtasn1-LGPL-2.1-or-later.txt"
    "$NOTICE_ROOT/licenses/libunistring-LGPL-3.0-or-later.txt"
    "$NOTICE_ROOT/licenses/libunistring-GPL-2.0-or-later.txt"
)

for required_file in "${required_files[@]}"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Distribution runtime is missing: $required_file" >&2
        exit 1
    fi
done

"$SCRIPT_DIR/verify-runtime-dependencies.sh" "$RUNTIME_ROOT" "$DEPLOYMENT_TARGET"

vendored_license_count=$(find "$NOTICE_ROOT/licenses" -type f -name 'Wine-vendored-*' | wc -l | tr -d ' ')
if (( vendored_license_count < 20 )); then
    echo "Distribution runtime is missing Wine-vendored license material." >&2
    exit 1
fi

/usr/bin/plutil -convert xml1 -o /dev/null "$NOTICE_ROOT/runtime-provenance.json"
/usr/bin/plutil -convert xml1 -o /dev/null "$NOTICE_ROOT/runtime-sbom.spdx.json"

if ! codesign -d --verbose=4 "$RUNTIME_ROOT/bin/secunda-rosetta-debug-broker" 2>&1 | \
    grep 'flags=.*runtime' >/dev/null; then
    echo "Runtime debug-register relay is missing its hardened-runtime signature." >&2
    exit 1
fi

if [[ -f "$REPOSITORY_ROOT/packaging/runtime-provenance.json" ]] && \
    ! cmp -s "$REPOSITORY_ROOT/packaging/runtime-provenance.json" "$NOTICE_ROOT/runtime-provenance.json"; then
    echo "Embedded runtime provenance does not match the canonical manifest." >&2
    exit 1
fi
if [[ -f "$REPOSITORY_ROOT/packaging/runtime-sbom.spdx.json" ]] && \
    ! cmp -s "$REPOSITORY_ROOT/packaging/runtime-sbom.spdx.json" "$NOTICE_ROOT/runtime-sbom.spdx.json"; then
    echo "Embedded runtime SBOM does not match the canonical SBOM." >&2
    exit 1
fi

if [[ $(/usr/bin/plutil -extract runtimeKind raw -o - "$NOTICE_ROOT/runtime-provenance.json") != "secunda-source-runtime" ]]; then
    echo "Runtime provenance kind is not source-only." >&2
    exit 1
fi

if [[ $(/usr/bin/plutil -extract minimumMacOS raw -o - "$NOTICE_ROOT/runtime-provenance.json") != "$DEPLOYMENT_TARGET" ]]; then
    echo "Runtime provenance minimum macOS does not match $DEPLOYMENT_TARGET." >&2
    exit 1
fi

"$SCRIPT_DIR/relocate-runtime.sh" "$RUNTIME_ROOT" --verify

is_newer_version() {
    awk -v actual="$1" -v maximum="$2" 'BEGIN {
        split(actual, a, "."); split(maximum, m, ".");
        if ((a[1] + 0) > (m[1] + 0)) exit 0;
        if ((a[1] + 0) < (m[1] + 0)) exit 1;
        exit ((a[2] + 0) > (m[2] + 0)) ? 0 : 1;
    }'
}

deployment_failure_count=0
mach_o_count=0
while IFS= read -r -d '' runtime_file; do
    file_description=$(file -b "$runtime_file" 2>/dev/null)
    [[ "$file_description" == *Mach-O* ]] || continue
    (( mach_o_count += 1 ))
    if [[ "$runtime_file" == "$RUNTIME_ROOT/bin/secunda-rosetta-debug-broker" ]]; then
        if [[ "$file_description" != *arm64* ]]; then
            echo "Runtime debug-register relay is not arm64: $runtime_file" >&2
            (( deployment_failure_count += 1 ))
        fi
    elif [[ "$file_description" != *x86_64* ]]; then
        echo "Runtime Mach-O does not contain x86_64 code: $runtime_file" >&2
        (( deployment_failure_count += 1 ))
    fi
    minimum_os=$(vtool -show-build "$runtime_file" 2>/dev/null | awk '/minos/{print $2; exit}')
    if [[ -z "$minimum_os" ]]; then
        echo "Missing macOS build version: $runtime_file" >&2
        (( deployment_failure_count += 1 ))
    elif is_newer_version "$minimum_os" "$DEPLOYMENT_TARGET"; then
        echo "Requires macOS $minimum_os (package target is $DEPLOYMENT_TARGET): $runtime_file" >&2
        (( deployment_failure_count += 1 ))
    fi
done < <(find "$RUNTIME_ROOT" -type f -print0)

for graphics_file in \
    "$RUNTIME_ROOT/lib/wine/x86_64-windows/d3d11.dll" \
    "$RUNTIME_ROOT/lib/wine/x86_64-windows/dxgi.dll"; do
    if [[ $(file -b "$graphics_file") != *x86-64* ]]; then
        echo "Graphics bridge is not x86-64: $graphics_file" >&2
        (( deployment_failure_count += 1 ))
    fi
done

if [[ $(file -b "$RUNTIME_ROOT/share/dxvk/x64/d3d9.dll") != *x86-64* ]]; then
    echo "DXVK 64-bit Direct3D 9 bridge has the wrong architecture." >&2
    (( deployment_failure_count += 1 ))
fi
if [[ $(file -b "$RUNTIME_ROOT/share/dxvk/x32/d3d9.dll") != *"Intel 80386"* ]]; then
    echo "DXVK 32-bit Direct3D 9 bridge has the wrong architecture." >&2
    (( deployment_failure_count += 1 ))
fi

if (( deployment_failure_count > 0 )); then
    echo "$deployment_failure_count Mach-O files exceed the package deployment target." >&2
    exit 1
fi

"$SCRIPT_DIR/verify-runtime-integrity.sh" "$RUNTIME_ROOT"

"$SCRIPT_DIR/verify-runtime-payload.sh" "$RUNTIME_ROOT"

echo "PASS: distributable source runtime verified ($mach_o_count Mach-O files, macOS $DEPLOYMENT_TARGET floor)."
