#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
FINAL_APP_ROOT="$REPOSITORY_ROOT/dist/Secunda Launcher.app"
mkdir -p "$REPOSITORY_ROOT/dist"
PACKAGE_STAGE=$(mktemp -d "$REPOSITORY_ROOT/dist/.secunda-app-stage.XXXXXX")
APP_RECOVERY_ROOT=$(mktemp -d "$REPOSITORY_ROOT/dist/.secunda-app-recovery.XXXXXX")
APP_ROOT="$PACKAGE_STAGE/Secunda Launcher.app"
CONTENTS="$APP_ROOT/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
RUNTIME_MODE="${SECUNDA_BUNDLE_RUNTIME:-0}"
RUNTIME_SOURCE=${SECUNDA_RUNTIME_SOURCE:-"$REPOSITORY_ROOT/Runtime/wine"}
SIGNING_IDENTITY="${SECUNDA_SIGNING_IDENTITY:--}"
WINE_ENTITLEMENTS="$REPOSITORY_ROOT/packaging/WineRuntime.entitlements"
PUBLISH_LOCK="$REPOSITORY_ROOT/dist/.secunda-app.publish.lock"
PUBLISH_LOCK_HELD=0
PRESERVE_PACKAGE_STAGE=0
PRESERVE_APP_RECOVERY=0
PREVIOUS_APP="$APP_RECOVERY_ROOT/Secunda Launcher.app"
PREVIOUS_LAUNCHER_SHA256=''
APP_TRANSACTION_ACTIVE=0
HAD_PREVIOUS_APP=0
NEW_APP_PUBLISHED=0

restore_previous_app() {
    local recovery_failed=0

    if (( NEW_APP_PUBLISHED == 1 )); then
        if [[ ( -e "$FINAL_APP_ROOT" || -L "$FINAL_APP_ROOT" ) && \
            ! -e "$APP_ROOT" && ! -L "$APP_ROOT" ]]; then
            mv "$FINAL_APP_ROOT" "$APP_ROOT" 2>/dev/null || recovery_failed=1
        else
            recovery_failed=1
        fi
    fi
    if (( HAD_PREVIOUS_APP == 1 )); then
        if [[ ( -e "$PREVIOUS_APP" || -L "$PREVIOUS_APP" ) && \
            ! -e "$FINAL_APP_ROOT" && ! -L "$FINAL_APP_ROOT" ]]; then
            mv "$PREVIOUS_APP" "$FINAL_APP_ROOT" 2>/dev/null || recovery_failed=1
        else
            recovery_failed=1
        fi
        if (( recovery_failed == 0 )) && \
            ! codesign --verify --deep --strict "$FINAL_APP_ROOT" >/dev/null 2>&1; then
            recovery_failed=1
        fi
        if (( recovery_failed == 0 )); then
            restored_launcher="$FINAL_APP_ROOT/Contents/MacOS/SecundaLauncher"
            restored_launcher_sha256=$(shasum -a 256 "$restored_launcher" | awk '{print $1}')
            [[ "$restored_launcher_sha256" == "$PREVIOUS_LAUNCHER_SHA256" ]] || \
                recovery_failed=1
        fi
    fi

    if (( recovery_failed == 0 )); then
        APP_TRANSACTION_ACTIVE=0
        PRESERVE_PACKAGE_STAGE=0
        PRESERVE_APP_RECOVERY=0
        echo "Restored the previous Secunda app after an interrupted publication." >&2
        return 0
    fi
    PRESERVE_PACKAGE_STAGE=1
    PRESERVE_APP_RECOVERY=1
    echo "Automatic app recovery was not proven; keep: $APP_RECOVERY_ROOT" >&2
    return 1
}

cleanup() {
    if (( ${APP_TRANSACTION_ACTIVE:-0} == 1 )); then
        restore_previous_app || true
    fi
    if (( ${PRESERVE_PACKAGE_STAGE:-0} == 1 )); then
        echo "Preserved failed app publication transaction for recovery: $PACKAGE_STAGE" >&2
    else
        rm -rf "$PACKAGE_STAGE"
    fi
    if (( ${PRESERVE_APP_RECOVERY:-0} == 1 )); then
        echo "Preserved previous app recovery data at: $APP_RECOVERY_ROOT" >&2
    else
        rm -rf "$APP_RECOVERY_ROOT"
    fi
    if (( ${PUBLISH_LOCK_HELD:-0} == 1 )); then
        rmdir "$PUBLISH_LOCK" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

sign_runtime_code() {
    local runtime_root=$1
    local runtime_file relative_file
    local signing_args

    while IFS= read -r -d '' runtime_file; do
        file -b "$runtime_file" 2>/dev/null | grep -q 'Mach-O' || continue
        relative_file=${runtime_file#"$runtime_root"/}
        signing_args=(--force --sign "$SIGNING_IDENTITY")
        if [[ "$SIGNING_IDENTITY" != "-" ]]; then
            signing_args+=(--options runtime --timestamp)
            case "$relative_file" in
                bin/wine|lib/wine/*-unix/wine)
                    signing_args+=(--entitlements "$WINE_ENTITLEMENTS")
                    ;;
            esac
        fi
        codesign "${signing_args[@]}" "$runtime_file"
    done < <(find "$runtime_root" -type f -print0)
}

cd "$REPOSITORY_ROOT"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/secunda-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/secunda-swiftpm-cache"
SWIFT_ARGS=(--disable-sandbox --triple arm64-apple-macosx15.0)
swift build "${SWIFT_ARGS[@]}" -c release --product SecundaLauncher
BIN_PATH=$(swift build "${SWIFT_ARGS[@]}" -c release --show-bin-path)

mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_PATH/SecundaLauncher" "$MACOS/SecundaLauncher"

while IFS= read -r launcher_rpath; do
    case "$launcher_rpath" in
        /usr/lib/*) ;;
        /*) install_name_tool -delete_rpath "$launcher_rpath" "$MACOS/SecundaLauncher" ;;
    esac
done < <(otool -l "$MACOS/SecundaLauncher" | awk '
    /cmd LC_RPATH/ { awaiting_path = 1; next }
    awaiting_path && /path / { print $2; awaiting_path = 0 }
')

case "$RUNTIME_MODE" in
    0|1) ;;
    *)
        echo "SECUNDA_BUNDLE_RUNTIME must be 0 or 1." >&2
        exit 64
        ;;
esac

# A share build must never inherit a stale local runtime from an older package.
rm -rf "$RESOURCES/runtime"
if [[ "$RUNTIME_MODE" == "1" ]]; then
    if [[ ! -x "$RUNTIME_SOURCE/bin/wine" ]]; then
        echo "SECUNDA_BUNDLE_RUNTIME=1 requires a complete runtime at $RUNTIME_SOURCE." >&2
        exit 1
    fi
    mkdir -p "$RESOURCES/runtime"
    ditto "$RUNTIME_SOURCE" "$RESOURCES/runtime"
    "$SCRIPT_DIR/relocate-runtime.sh" "$RESOURCES/runtime" --fix
fi

cp "$REPOSITORY_ROOT/packaging/Info.plist" "$CONTENTS/Info.plist"
mkdir -p "$RESOURCES"
cp "$REPOSITORY_ROOT/packaging/Secunda.icns" "$RESOURCES/Secunda.icns"
OUTER_SIGNING_ARGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    OUTER_SIGNING_ARGS+=(--options runtime --timestamp)
fi

if [[ "$RUNTIME_MODE" == "1" ]]; then
    "$SCRIPT_DIR/stage-runtime-notices.sh" "$RESOURCES/runtime"
    sign_runtime_code "$RESOURCES/runtime"
    "$SCRIPT_DIR/create-runtime-integrity.sh" "$RESOURCES/runtime"
fi
codesign "${OUTER_SIGNING_ARGS[@]}" "$APP_ROOT"
if [[ "$RUNTIME_MODE" == "1" ]]; then
    "$SCRIPT_DIR/verify-packaged-app.sh" "$APP_ROOT"
fi
codesign --verify --deep --strict "$APP_ROOT"

if ! mkdir "$PUBLISH_LOCK" 2>/dev/null; then
    echo "Another Secunda app publisher holds the output lock: $PUBLISH_LOCK" >&2
    exit 1
fi
PUBLISH_LOCK_HELD=1
PRESERVE_PACKAGE_STAGE=1
APP_TRANSACTION_ACTIVE=1
if [[ -e "$FINAL_APP_ROOT" || -L "$FINAL_APP_ROOT" ]]; then
    PREVIOUS_LAUNCHER_SHA256=$(shasum -a 256 \
        "$FINAL_APP_ROOT/Contents/MacOS/SecundaLauncher" | awk '{print $1}')
    PRESERVE_APP_RECOVERY=1
    HAD_PREVIOUS_APP=1
    if ! mv "$FINAL_APP_ROOT" "$PREVIOUS_APP"; then
        echo "Failed to preserve the previous Secunda app before publication." >&2
        exit 1
    fi
fi
NEW_APP_PUBLISHED=1
if ! mv "$APP_ROOT" "$FINAL_APP_ROOT"; then
    echo "Failed to publish the verified Secunda app." >&2
    exit 1
fi
APP_TRANSACTION_ACTIVE=0
if ! rmdir "$PUBLISH_LOCK"; then
    echo "App published, but its output lock could not be released: $PUBLISH_LOCK" >&2
    exit 1
fi
PUBLISH_LOCK_HELD=0
PRESERVE_PACKAGE_STAGE=0
PRESERVE_APP_RECOVERY=0

echo "Built: $FINAL_APP_ROOT"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "This local build is ad-hoc signed. Use a Developer ID identity and notarization before broad sharing."
else
    echo "Signed with: $SIGNING_IDENTITY"
fi
