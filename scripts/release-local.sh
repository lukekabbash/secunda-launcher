#!/bin/zsh
# Build, sign, notarize and prepare one Secunda release on this Mac.
# Nothing here pushes, tags or uploads, so no GitHub Actions run.
#
#   scripts/release-local.sh 0.1.6                 # Developer ID + notarized
#   scripts/release-local.sh 0.1.6 --test-only     # ad-hoc, not notarized
#
# Options:
#   --runtime PATH   Wine runtime to bundle. Defaults to Runtime/wine-macos15.
#                    A runtime taken from a packaged Secunda app is accepted
#                    only after its integrity manifest verifies.
#   --keep-version   Do not change packaging/Info.plist (rebuild same version).
#
# Environment:
#   SECUNDA_SIGNING_IDENTITY  Defaults to the first "Developer ID Application"
#                             identity in the keychain.
#   SECUNDA_NOTARY_PROFILE    notarytool keychain profile. Default secunda-notary.
#   SECUNDA_RELEASE_TAG       Defaults to secunda-VERSION. Tags that start with
#                             "v" would start the package-share-dmg workflow.
#   SECUNDA_DOWNLOAD_BASE_URL Where the DMG will live. Defaults to the GitHub
#                             release download URL for the tag.
#
# Output in dist/release/VERSION/: the DMG, its SHA-256, appcast.xml for the
# in-app updater, release.json for the website, and the publish commands.
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
INFO_PLIST="$REPOSITORY_ROOT/packaging/Info.plist"
SPARKLE_ACCOUNT=secunda-launcher
REPOSITORY_SLUG=lukekabbash/secunda-launcher
SOURCE_ARCHIVE_NAME=crossover-sources-26.3.0.tar.gz
NETTLE_ARCHIVE_NAME=nettle-3.10.tar.gz
SOURCE_CACHE="$REPOSITORY_ROOT/build/source-cache"

VERSION=''
TEST_ONLY=0
KEEP_VERSION=0
RUNTIME_SOURCE="$REPOSITORY_ROOT/Runtime/wine-macos15"
while (( $# > 0 )); do
    case "$1" in
        --test-only) TEST_ONLY=1 ;;
        --keep-version) KEEP_VERSION=1 ;;
        --runtime) shift; RUNTIME_SOURCE=${1:?--runtime needs a path} ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; exit 64 ;;
        *) [[ -z "$VERSION" ]] || { echo "Only one version is allowed." >&2; exit 64; }
           VERSION=$1 ;;
    esac
    shift
done
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Usage: $0 MAJOR.MINOR.PATCH [--test-only] [--runtime PATH] [--keep-version]" >&2
    exit 64
fi
RUNTIME_SOURCE=${RUNTIME_SOURCE:A}

plist_get() { /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"; }
CURRENT_VERSION=$(plist_get CFBundleShortVersionString)
CURRENT_BUILD=$(plist_get CFBundleVersion)

version_greater() {
    # True when $1 > $2 for MAJOR.MINOR.PATCH strings.
    local IFS=.
    local -a a=(${=1}) b=(${=2})
    local i
    for i in 1 2 3; do
        (( a[i] > b[i] )) && return 0
        (( a[i] < b[i] )) && return 1
    done
    return 1
}

if (( KEEP_VERSION == 1 )); then
    [[ "$VERSION" == "$CURRENT_VERSION" ]] || {
        echo "--keep-version needs VERSION to equal the current $CURRENT_VERSION." >&2
        exit 64
    }
    BUILD_NUMBER=$CURRENT_BUILD
elif ! version_greater "$VERSION" "$CURRENT_VERSION"; then
    echo "$VERSION is not newer than the current $CURRENT_VERSION." >&2
    echo "Use --keep-version to rebuild $CURRENT_VERSION." >&2
    exit 64
else
    BUILD_NUMBER=$(( CURRENT_BUILD + 1 ))
fi

# --- Signing mode ---------------------------------------------------------
if (( TEST_ONLY == 1 )); then
    SIGNING_IDENTITY=-
    NOTARY_PROFILE=''
else
    SIGNING_IDENTITY=${SECUNDA_SIGNING_IDENTITY:-$(
        security find-identity -v -p codesigning |
            sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1
    )}
    if [[ "$SIGNING_IDENTITY" != "Developer ID Application: "* ]]; then
        echo "No Developer ID Application identity found. Use --test-only for a local build." >&2
        exit 1
    fi
    NOTARY_PROFILE=${SECUNDA_NOTARY_PROFILE:-secunda-notary}
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        TEAM_ID=$(print -r -- "$SIGNING_IDENTITY" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
        echo "Notarization profile '$NOTARY_PROFILE' is not set up. Run this once:" >&2
        echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id YOUR_APPLE_ID --team-id $TEAM_ID" >&2
        echo "It asks for an app-specific password from account.apple.com." >&2
        exit 1
    fi
fi

# --- Sparkle tools and key ------------------------------------------------
SPARKLE_BIN=$("$SCRIPT_DIR/fetch-sparkle-tools.sh")
PLIST_PUBLIC_KEY=$(plist_get SUPublicEDKey)
KEYCHAIN_PUBLIC_KEY=$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null || true)
if [[ -z "$KEYCHAIN_PUBLIC_KEY" || "$KEYCHAIN_PUBLIC_KEY" != "$PLIST_PUBLIC_KEY" ]]; then
    echo "The Sparkle signing key in Keychain (account $SPARKLE_ACCOUNT) does not match" >&2
    echo "SUPublicEDKey in packaging/Info.plist. Updates signed now would be rejected." >&2
    exit 1
fi

# --- Source inputs (shipped in the DMG for license compliance) -------------
mkdir -p "$SOURCE_CACHE"
EXPECTED_SOURCE_SHA256=$(/usr/bin/plutil -extract sourceArchive.sha256 raw -o - \
    "$REPOSITORY_ROOT/packaging/runtime-provenance.json")
EXPECTED_NETTLE_SHA256=$(/usr/bin/python3 -I -c '
import json, sys
data = json.load(open(sys.argv[1]))
print(next(c["archiveSha256"] for c in data["components"] if c["name"] == "Nettle"))
' "$REPOSITORY_ROOT/packaging/runtime-provenance.json")

sha256_of() { /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'; }

SOURCE_ARCHIVE="$SOURCE_CACHE/$SOURCE_ARCHIVE_NAME"
if [[ ! -f "$SOURCE_ARCHIVE" ]] || [[ $(sha256_of "$SOURCE_ARCHIVE") != "$EXPECTED_SOURCE_SHA256" ]]; then
    rm -f "$SOURCE_ARCHIVE"
    for candidate in "${SECUNDA_SOURCE_ARCHIVE:-}" "$REPOSITORY_ROOT/$SOURCE_ARCHIVE_NAME" \
        "$HOME/Downloads/$SOURCE_ARCHIVE_NAME"; do
        [[ -n "$candidate" && -f "$candidate" ]] || continue
        if [[ $(sha256_of "$candidate") == "$EXPECTED_SOURCE_SHA256" ]]; then
            cp "$candidate" "$SOURCE_ARCHIVE"
            break
        fi
    done
fi
if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    echo "Downloading $SOURCE_ARCHIVE_NAME from CodeWeavers."
    /usr/bin/curl --fail --location --retry 5 --proto '=https' --output "$SOURCE_ARCHIVE" \
        "https://media.codeweavers.com/pub/crossover/source/$SOURCE_ARCHIVE_NAME"
fi
[[ $(sha256_of "$SOURCE_ARCHIVE") == "$EXPECTED_SOURCE_SHA256" ]] || {
    echo "Source archive checksum mismatch." >&2; exit 1; }

NETTLE_ARCHIVE="$SOURCE_CACHE/$NETTLE_ARCHIVE_NAME"
if [[ ! -f "$NETTLE_ARCHIVE" ]] || [[ $(sha256_of "$NETTLE_ARCHIVE") != "$EXPECTED_NETTLE_SHA256" ]]; then
    rm -f "$NETTLE_ARCHIVE"
    /usr/bin/curl --fail --location --retry 5 --proto '=https' --output "$NETTLE_ARCHIVE" \
        "https://ftp.gnu.org/gnu/nettle/$NETTLE_ARCHIVE_NAME"
fi
[[ $(sha256_of "$NETTLE_ARCHIVE") == "$EXPECTED_NETTLE_SHA256" ]] || {
    echo "Nettle archive checksum mismatch." >&2; exit 1; }

# --- Runtime ----------------------------------------------------------------
if [[ ! -x "$RUNTIME_SOURCE/bin/wine" ]]; then
    echo "No Wine runtime at $RUNTIME_SOURCE." >&2
    echo "Build one with scripts/build-runtime-from-archive.sh, or reuse a released one:" >&2
    echo "  $0 $VERSION --runtime \"/Applications/Secunda Launcher.app/Contents/Resources/runtime\"" >&2
    exit 1
fi
if [[ -f "$RUNTIME_SOURCE/share/secunda/runtime-files.sha256" ]]; then
    echo "Verifying the reused runtime against its integrity manifest."
    "$SCRIPT_DIR/verify-runtime-integrity.sh" "$RUNTIME_SOURCE"
fi

# --- Version bump, restored if packaging fails ------------------------------
PLIST_BACKUP=$(mktemp "${TMPDIR:-/tmp}/secunda-info-plist.XXXXXX")
cp "$INFO_PLIST" "$PLIST_BACKUP"
RELEASE_SUCCEEDED=0
restore_plist() {
    if (( RELEASE_SUCCEEDED == 0 )); then
        cp "$PLIST_BACKUP" "$INFO_PLIST"
    fi
    rm -f "$PLIST_BACKUP"
}
trap restore_plist EXIT
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"

# --- Build, sign, notarize --------------------------------------------------
SECUNDA_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
SECUNDA_NOTARY_PROFILE="$NOTARY_PROFILE" \
SECUNDA_TEST_ONLY_UNNOTARIZED_DMG="$TEST_ONLY" \
SECUNDA_SOURCE_ARCHIVE="$SOURCE_ARCHIVE" \
SECUNDA_RUNTIME_SOURCE="$RUNTIME_SOURCE" \
    "$SCRIPT_DIR/package-share-dmg.sh"

if (( TEST_ONLY == 1 )); then
    BUILT_DMG="$REPOSITORY_ROOT/dist/Secunda Launcher-${VERSION}-TEST-ONLY.dmg"
    ASSET_NAME="Secunda-Launcher-${VERSION}-TEST-ONLY.dmg"
else
    BUILT_DMG="$REPOSITORY_ROOT/dist/Secunda Launcher-${VERSION}.dmg"
    ASSET_NAME="Secunda-Launcher-${VERSION}.dmg"
fi
RELEASE_DIR="$REPOSITORY_ROOT/dist/release/$VERSION"
mkdir -p "$RELEASE_DIR"
ASSET="$RELEASE_DIR/$ASSET_NAME"
ditto "$BUILT_DMG" "$ASSET"
DMG_SHA256=$(sha256_of "$ASSET")
print -r -- "$DMG_SHA256  $ASSET_NAME" > "$ASSET.sha256"

# --- Sparkle signature and feed ---------------------------------------------
SIGNATURE_ATTRIBUTES=$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$ASSET")
ED_SIGNATURE=$(print -r -- "$SIGNATURE_ATTRIBUTES" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
DMG_LENGTH=$(print -r -- "$SIGNATURE_ATTRIBUTES" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')
[[ -n "$ED_SIGNATURE" && -n "$DMG_LENGTH" ]] || {
    echo "sign_update returned no signature: $SIGNATURE_ATTRIBUTES" >&2; exit 1; }

RELEASE_TAG=${SECUNDA_RELEASE_TAG:-secunda-$VERSION}
if [[ "$RELEASE_TAG" == v* ]]; then
    echo "Release tags starting with 'v' start the package-share-dmg workflow. Pick another tag." >&2
    exit 64
fi
DOWNLOAD_BASE_URL=${SECUNDA_DOWNLOAD_BASE_URL:-"https://github.com/$REPOSITORY_SLUG/releases/download/$RELEASE_TAG"}
DOWNLOAD_URL="$DOWNLOAD_BASE_URL/$ASSET_NAME"
NOTES_FILE="$REPOSITORY_ROOT/packaging/release-notes/v$VERSION.md"
MINIMUM_OS=$(plist_get LSMinimumSystemVersion)

/usr/bin/python3 -I - "$RELEASE_DIR" "$VERSION" "$BUILD_NUMBER" "$DOWNLOAD_URL" \
    "$ED_SIGNATURE" "$DMG_LENGTH" "$DMG_SHA256" "$MINIMUM_OS" "$NOTES_FILE" \
    "$TEST_ONLY" <<'PY'
import html, json, os, sys
from datetime import datetime, timezone
from email.utils import format_datetime

(release_dir, version, build, url, signature, length, sha256,
 minimum_os, notes_file, test_only) = sys.argv[1:]

def notes_html(path):
    """Tiny Markdown subset: headings, bullets, paragraphs."""
    if not os.path.isfile(path):
        return f"<p>Secunda Launcher {html.escape(version)}.</p>"
    out, bullets, para = [], [], []
    def flush():
        if para:
            out.append("<p>" + html.escape(" ".join(para)) + "</p>"); para.clear()
        if bullets:
            out.append("<ul>" + "".join(f"<li>{html.escape(b)}</li>" for b in bullets) + "</ul>")
            bullets.clear()
    for raw in open(path, encoding="utf-8"):
        line = raw.strip()
        if not line:
            flush()
        elif line.startswith("#"):
            flush()
            level = min(len(line) - len(line.lstrip("#")) + 1, 4)
            out.append(f"<h{level}>{html.escape(line.lstrip('#').strip())}</h{level}>")
        elif line.startswith(("- ", "* ")):
            if para: flush()
            bullets.append(line[2:].strip())
        else:
            if bullets: flush()
            para.append(line)
    flush()
    return "\n".join(out)

now = datetime.now(timezone.utc).replace(microsecond=0)
notes = notes_html(notes_file)
title = f"Secunda Launcher {version}" + (" (TEST-ONLY)" if test_only == "1" else "")
appcast = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Secunda Launcher</title>
    <item>
      <title>{html.escape(title)}</title>
      <pubDate>{format_datetime(now)}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{html.escape(minimum_os)}</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{html.escape(url, quote=True)}"
                 length="{html.escape(length)}"
                 type="application/x-apple-diskimage"
                 sparkle:edSignature="{html.escape(signature, quote=True)}" />
    </item>
  </channel>
</rss>
"""
with open(os.path.join(release_dir, "appcast.xml"), "w", encoding="utf-8") as f:
    f.write(appcast)

release = {
    "version": version,
    "build": int(build),
    "published": now.isoformat().replace("+00:00", "Z"),
    "minimumSystemVersion": minimum_os,
    "downloadURL": url,
    "sizeBytes": int(length),
    "sha256": sha256,
    "testOnly": test_only == "1",
}
with open(os.path.join(release_dir, "release.json"), "w", encoding="utf-8") as f:
    json.dump(release, f, indent=2)
    f.write("\n")
PY

if (( TEST_ONLY == 1 )); then
    TRUST_LINE="TEST-ONLY: ad-hoc signed and not notarized. Use it on this Mac only;
do not publish it. Other Macs will block it, and the updater would offer it."
else
    TRUST_LINE="Signed with $SIGNING_IDENTITY and notarized by Apple."
fi
cat > "$RELEASE_DIR/PUBLISH.txt" <<EOF
Secunda $VERSION is built. Nothing has been uploaded.
$TRUST_LINE

To publish on GitHub Releases (the tag does not start with "v", so no
workflow runs):

  gh release create $RELEASE_TAG --repo $REPOSITORY_SLUG \\
    --title "Secunda Launcher $VERSION" \\
    --notes-file "$NOTES_FILE" \\
    "$ASSET" "$ASSET.sha256" "$RELEASE_DIR/appcast.xml"

The in-app updater reads appcast.xml from the latest release, so it must be
attached to every release. Copy release.json into site/ before deploying the
website so its download button points at this DMG.
EOF

RELEASE_SUCCEEDED=1
echo
echo "Release $VERSION (build $BUILD_NUMBER) is in $RELEASE_DIR"
cat "$RELEASE_DIR/PUBLISH.txt"
