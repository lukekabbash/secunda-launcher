#!/bin/zsh
set -euo pipefail

CANDIDATE_DMG=${1:-}
CANDIDATE_CHECKSUM=${2:-}
FINAL_DMG=${3:-}
FINAL_CHECKSUM=${4:-}
LOCK_HELD=0

if [[ -z "$CANDIDATE_DMG" || -z "$CANDIDATE_CHECKSUM" || \
    -z "$FINAL_DMG" || -z "$FINAL_CHECKSUM" ]]; then
    echo "Usage: $0 candidate.dmg candidate.dmg.sha256 final.dmg final.dmg.sha256" >&2
    exit 64
fi

CANDIDATE_DMG=${CANDIDATE_DMG:A}
CANDIDATE_CHECKSUM=${CANDIDATE_CHECKSUM:A}
FINAL_DMG=${FINAL_DMG:A}
FINAL_CHECKSUM=${FINAL_CHECKSUM:A}
PUBLISH_LOCK="${FINAL_DMG:h}/.secunda-dmg.publish.lock"
RECOVERY_ROOT=$(mktemp -d "${FINAL_DMG:h}/.secunda-dmg-recovery.XXXXXX")
BACKUP_DMG="$RECOVERY_ROOT/previous-release.dmg"
BACKUP_CHECKSUM="$RECOVERY_ROOT/previous-release.dmg.sha256"
PRESERVE_RECOVERY_ROOT=0
HAD_PREVIOUS_DMG=0
HAD_PREVIOUS_CHECKSUM=0
NEW_DMG_PUBLISHED=0
NEW_CHECKSUM_PUBLISHED=0
TRANSACTION_ACTIVE=0
PREVIOUS_DMG_SHA256=''
PREVIOUS_CHECKSUM_SHA256=''

restore_previous_pair() {
    local recovery_failed=0

    if (( NEW_CHECKSUM_PUBLISHED == 1 )); then
        if [[ ( -e "$FINAL_CHECKSUM" || -L "$FINAL_CHECKSUM" ) && \
            ! -e "$CANDIDATE_CHECKSUM" && ! -L "$CANDIDATE_CHECKSUM" ]]; then
            mv "$FINAL_CHECKSUM" "$CANDIDATE_CHECKSUM" 2>/dev/null || recovery_failed=1
        else
            recovery_failed=1
        fi
    fi
    if (( NEW_DMG_PUBLISHED == 1 )); then
        if [[ ( -e "$FINAL_DMG" || -L "$FINAL_DMG" ) && \
            ! -e "$CANDIDATE_DMG" && ! -L "$CANDIDATE_DMG" ]]; then
            mv "$FINAL_DMG" "$CANDIDATE_DMG" 2>/dev/null || recovery_failed=1
        else
            recovery_failed=1
        fi
    fi
    if (( HAD_PREVIOUS_DMG == 1 )); then
        if [[ ( -e "$BACKUP_DMG" || -L "$BACKUP_DMG" ) && \
            ! -e "$FINAL_DMG" && ! -L "$FINAL_DMG" ]]; then
            mv "$BACKUP_DMG" "$FINAL_DMG" 2>/dev/null || recovery_failed=1
        else
            recovery_failed=1
        fi
    fi
    if (( HAD_PREVIOUS_CHECKSUM == 1 )); then
        if [[ ( -e "$BACKUP_CHECKSUM" || -L "$BACKUP_CHECKSUM" ) && \
            ! -e "$FINAL_CHECKSUM" && ! -L "$FINAL_CHECKSUM" ]]; then
            mv "$BACKUP_CHECKSUM" "$FINAL_CHECKSUM" 2>/dev/null || recovery_failed=1
        else
            recovery_failed=1
        fi
    fi
    if (( HAD_PREVIOUS_DMG == 1 )) && [[ -f "$FINAL_DMG" ]]; then
        restored_dmg_sha256=$(shasum -a 256 "$FINAL_DMG" | awk '{print $1}')
        [[ "$restored_dmg_sha256" == "$PREVIOUS_DMG_SHA256" ]] || recovery_failed=1
    fi
    if (( HAD_PREVIOUS_CHECKSUM == 1 )) && [[ -f "$FINAL_CHECKSUM" ]]; then
        restored_checksum_sha256=$(shasum -a 256 "$FINAL_CHECKSUM" | awk '{print $1}')
        [[ "$restored_checksum_sha256" == "$PREVIOUS_CHECKSUM_SHA256" ]] || recovery_failed=1
    fi

    if (( recovery_failed == 0 )); then
        TRANSACTION_ACTIVE=0
        PRESERVE_RECOVERY_ROOT=0
        echo "Restored the previous DMG pair after an interrupted publication." >&2
        return 0
    fi
    PRESERVE_RECOVERY_ROOT=1
    echo "Automatic DMG recovery was not proven; keep: $RECOVERY_ROOT" >&2
    return 1
}

cleanup() {
    if (( ${TRANSACTION_ACTIVE:-0} == 1 )); then
        restore_previous_pair || true
    fi
    if (( ${LOCK_HELD:-0} == 1 )); then
        rmdir "$PUBLISH_LOCK" 2>/dev/null || true
    fi
    if (( ${PRESERVE_RECOVERY_ROOT:-0} == 1 )); then
        echo "Preserved previous DMG recovery data at: $RECOVERY_ROOT" >&2
    else
        rm -rf "$RECOVERY_ROOT"
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -f "$CANDIDATE_DMG" || -L "$CANDIDATE_DMG" || \
    ! -f "$CANDIDATE_CHECKSUM" || -L "$CANDIDATE_CHECKSUM" ]]; then
    echo "Verified DMG candidate pair is incomplete." >&2
    exit 1
fi
if [[ "${CANDIDATE_DMG:t}" != "${FINAL_DMG:t}" || \
    "${CANDIDATE_CHECKSUM:t}" != "${FINAL_CHECKSUM:t}" ]]; then
    echo "DMG candidate and final names must match." >&2
    exit 1
fi
if [[ -e "$BACKUP_DMG" || -L "$BACKUP_DMG" || \
    -e "$BACKUP_CHECKSUM" || -L "$BACKUP_CHECKSUM" ]]; then
    echo "DMG publication backup paths are unexpectedly occupied." >&2
    exit 1
fi
if ! mkdir "$PUBLISH_LOCK" 2>/dev/null; then
    echo "Another DMG publisher holds the output lock: $PUBLISH_LOCK" >&2
    exit 1
fi
LOCK_HELD=1
TRANSACTION_ACTIVE=1

if [[ -e "$FINAL_DMG" || -L "$FINAL_DMG" ]]; then
    PREVIOUS_DMG_SHA256=$(shasum -a 256 "$FINAL_DMG" | awk '{print $1}')
    PRESERVE_RECOVERY_ROOT=1
    HAD_PREVIOUS_DMG=1
    if ! mv "$FINAL_DMG" "$BACKUP_DMG"; then
        echo "Failed to preserve the previous DMG before publication." >&2
        exit 1
    fi
fi
if [[ -e "$FINAL_CHECKSUM" || -L "$FINAL_CHECKSUM" ]]; then
    PREVIOUS_CHECKSUM_SHA256=$(shasum -a 256 "$FINAL_CHECKSUM" | awk '{print $1}')
    PRESERVE_RECOVERY_ROOT=1
    HAD_PREVIOUS_CHECKSUM=1
    if ! mv "$FINAL_CHECKSUM" "$BACKUP_CHECKSUM"; then
        echo "Failed to preserve the previous DMG checksum before publication." >&2
        exit 1
    fi
fi
NEW_DMG_PUBLISHED=1
if ! mv "$CANDIDATE_DMG" "$FINAL_DMG"; then
    echo "Failed to publish the verified DMG candidate." >&2
    exit 1
fi
NEW_CHECKSUM_PUBLISHED=1
if ! mv "$CANDIDATE_CHECKSUM" "$FINAL_CHECKSUM"; then
    echo "Failed to publish the verified DMG checksum." >&2
    exit 1
fi
TRANSACTION_ACTIVE=0
if ! rmdir "$PUBLISH_LOCK"; then
    echo "DMG pair published, but its output lock could not be released: $PUBLISH_LOCK" >&2
    exit 1
fi
LOCK_HELD=0
PRESERVE_RECOVERY_ROOT=0

echo "PASS: verified DMG and checksum published as one locked transaction."
