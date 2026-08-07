#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
PAYLOAD_ROOT=${1:-"$REPOSITORY_ROOT/Runtime/wine"}
PAYLOAD_ROOT=${PAYLOAD_ROOT:A}

if [[ ! -d "$PAYLOAD_ROOT" ]]; then
    echo "Payload root does not exist: $PAYLOAD_ROOT" >&2
    exit 1
fi

forbidden_path=$(find "$PAYLOAD_ROOT" \( \
    -iname 'steam.exe' -o \
    -iname 'skyrimse.exe' -o \
    -iname 'loginusers.vdf' -o \
    -iname 'config.vdf' -o \
    -iname 'registry.vdf' -o \
    -iname 'localconfig.vdf' -o \
    -iname 'ssfn*' -o \
    -iname '*.ess' -o \
    -iname '*.ess.bak' -o \
    -iname '*.log' -o \
    -iname 'system.reg' -o \
    -iname 'user.reg' -o \
    -iname 'userdef.reg' -o \
    -iname '*d3dmetal*' -o \
    -iname '*d3dshared*' -o \
    -iname '*apple_gptk*' -o \
    -iname 'CrossOver.app' -o \
    -type d -iname 'userdata' -o \
    -type d -iname 'steamapps' -o \
    -type d -iname 'drive_c' -o \
    -type d -iname 'dosdevices' \
\) -print -quit)

if [[ -n "$forbidden_path" ]]; then
    echo "Forbidden proprietary or user payload: $forbidden_path" >&2
    exit 1
fi

echo "PASS: no proprietary runtime, Steam session, game, prefix, save, or log payload was found."
