#!/bin/zsh
set -euo pipefail

# Stages the Direct3D 9 Vulkan stack into the runtime: MoltenVK (Vulkan over
# Metal, Apache-2.0) and DXVK's d3d9 (D3D9 over Vulkan, Zlib). Both are
# official tagged releases, checksum-verified, recorded in
# packaging/runtime-provenance.json and licenses/.

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
RUNTIME_ROOT=${1:-"$REPOSITORY_ROOT/Runtime/wine"}

MOLTENVK_VERSION="1.4.2"
MOLTENVK_SHA256="f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e"
MOLTENVK_URL="https://github.com/KhronosGroup/MoltenVK/releases/download/v${MOLTENVK_VERSION}/MoltenVK-macos.tar"

DXVK_VERSION="1.10.3"
DXVK_SHA256="8d1a3c912761b450c879f98478ae64f6f6639e40ce6848170a0f6b8596fd53c6"
DXVK_URL="https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz"

STAGE_ROOT=$(mktemp -d /private/tmp/secunda-vulkan.XXXXXX)
cleanup() {
    rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

if [[ ! -d "$RUNTIME_ROOT/lib" ]]; then
    echo "Runtime library directory not found: $RUNTIME_ROOT/lib" >&2
    exit 1
fi

fetch_verified() {
    local url=$1 expected=$2 output=$3
    curl -fL "$url" -o "$output"
    local actual
    actual=$(shasum -a 256 "$output" | awk '{print $1}')
    if [[ "$actual" != "$expected" ]]; then
        echo "Checksum mismatch for $url" >&2
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        exit 1
    fi
}

fetch_verified "$MOLTENVK_URL" "$MOLTENVK_SHA256" "$STAGE_ROOT/moltenvk.tar"
tar -xf "$STAGE_ROOT/moltenvk.tar" -C "$STAGE_ROOT"
cp "$STAGE_ROOT/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" \
    "$RUNTIME_ROOT/lib/libMoltenVK.dylib"
codesign --force --sign - "$RUNTIME_ROOT/lib/libMoltenVK.dylib"

fetch_verified "$DXVK_URL" "$DXVK_SHA256" "$STAGE_ROOT/dxvk.tar.gz"
tar -xzf "$STAGE_ROOT/dxvk.tar.gz" -C "$STAGE_ROOT"
mkdir -p "$RUNTIME_ROOT/share/dxvk/x32" "$RUNTIME_ROOT/share/dxvk/x64"
cp "$STAGE_ROOT/dxvk-${DXVK_VERSION}/x32/d3d9.dll" "$RUNTIME_ROOT/share/dxvk/x32/d3d9.dll"
cp "$STAGE_ROOT/dxvk-${DXVK_VERSION}/x64/d3d9.dll" "$RUNTIME_ROOT/share/dxvk/x64/d3d9.dll"

for required_file in \
    "$RUNTIME_ROOT/lib/libMoltenVK.dylib" \
    "$RUNTIME_ROOT/share/dxvk/x32/d3d9.dll" \
    "$RUNTIME_ROOT/share/dxvk/x64/d3d9.dll"; do
    if [[ ! -f "$required_file" ]]; then
        echo "Missing Vulkan stack file: $required_file" >&2
        exit 1
    fi
done

echo "${MOLTENVK_VERSION}+dxvk-${DXVK_VERSION}" > "$RUNTIME_ROOT/lib/.secunda-vulkan-stack-version"

echo "MoltenVK v${MOLTENVK_VERSION} and DXVK v${DXVK_VERSION} verified and staged in $RUNTIME_ROOT"
