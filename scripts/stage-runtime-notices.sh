#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPOSITORY_ROOT=${SCRIPT_DIR:h}
SOURCE_ROOT=${SECUNDA_SOURCE_ROOT:-"$REPOSITORY_ROOT/sources"}
RUNTIME_ROOT=${1:-"$REPOSITORY_ROOT/Runtime/wine"}
RUNTIME_ROOT=${RUNTIME_ROOT:A}
NOTICE_ROOT="$RUNTIME_ROOT/share/secunda"
LICENSE_ROOT="$NOTICE_ROOT/licenses"

if [[ ! -d "$RUNTIME_ROOT" || ! -x "$RUNTIME_ROOT/bin/wine" ]]; then
    echo "Incomplete Secunda runtime: $RUNTIME_ROOT" >&2
    exit 1
fi

license_sources=(
    "$SOURCE_ROOT/wine/LICENSE"
    "$SOURCE_ROOT/wine/AUTHORS"
    "$SOURCE_ROOT/wine/COPYING.LIB"
    "$REPOSITORY_ROOT/licenses/DXMT-v0.80-LICENSE.txt"
    "$REPOSITORY_ROOT/licenses/DXVK-v1.10.3-LICENSE.txt"
    "$REPOSITORY_ROOT/licenses/MoltenVK-v1.4.2-LICENSE.txt"
    "$SOURCE_ROOT/freetype/docs/FTL.TXT"
    "$SOURCE_ROOT/gnutls/gmp/COPYING.LESSERv3"
    "$SOURCE_ROOT/gnutls/gmp/COPYINGv3"
    "$SOURCE_ROOT/gnutls/nettle/COPYING.LESSERv3"
    "$SOURCE_ROOT/gnutls/nettle/COPYINGv3"
    "$SOURCE_ROOT/gnutls/gnutls/LICENSE"
    "$SOURCE_ROOT/gnutls/gnutls/doc/COPYING.LESSER"
    "$SOURCE_ROOT/wine/libs/capstone/LICENSE.TXT"
    "$SOURCE_ROOT/wine/libs/capstone/LICENSE_LLVM.TXT"
    "$SOURCE_ROOT/wine/libs/compiler-rt/LICENSE.TXT"
    "$SOURCE_ROOT/wine/libs/faudio/LICENSE"
    "$SOURCE_ROOT/wine/libs/fluidsynth/COPYING.md"
    "$SOURCE_ROOT/wine/libs/gsm/COPYRIGHT"
    "$SOURCE_ROOT/wine/libs/jpeg/LICENSE"
    "$SOURCE_ROOT/wine/libs/jxr/LICENSE"
    "$SOURCE_ROOT/wine/libs/lcms2/COPYING"
    "$SOURCE_ROOT/wine/libs/ldap/LICENSE"
    "$SOURCE_ROOT/wine/libs/ldap/COPYRIGHT"
    "$SOURCE_ROOT/wine/libs/mpg123/LICENSE"
    "$SOURCE_ROOT/wine/libs/musl/COPYRIGHT"
    "$SOURCE_ROOT/wine/libs/png/LICENSE"
    "$SOURCE_ROOT/wine/libs/tiff/COPYRIGHT"
    "$SOURCE_ROOT/wine/libs/tomcrypt/LICENSE"
    "$SOURCE_ROOT/wine/libs/vkd3d/COPYING"
    "$SOURCE_ROOT/wine/libs/xml2/COPYING"
    "$SOURCE_ROOT/wine/libs/xslt/COPYING"
    "$SOURCE_ROOT/wine/libs/zlib/LICENSE"
)

for license_source in "${license_sources[@]}"; do
    if [[ ! -f "$license_source" ]]; then
        echo "Required license file is missing: $license_source" >&2
        exit 1
    fi
done

mkdir -p "$LICENSE_ROOT"
install -m 0644 "$REPOSITORY_ROOT/packaging/THIRD_PARTY_NOTICES.txt" \
    "$NOTICE_ROOT/THIRD_PARTY_NOTICES.txt"
install -m 0644 "$REPOSITORY_ROOT/packaging/runtime-provenance.json" \
    "$NOTICE_ROOT/runtime-provenance.json"
install -m 0644 "$REPOSITORY_ROOT/packaging/runtime-sbom.spdx.json" \
    "$NOTICE_ROOT/runtime-sbom.spdx.json"
install -m 0644 "$SOURCE_ROOT/wine/LICENSE" \
    "$LICENSE_ROOT/Wine-NOTICE.txt"
install -m 0644 "$SOURCE_ROOT/wine/AUTHORS" \
    "$LICENSE_ROOT/Wine-AUTHORS.txt"
install -m 0644 "$SOURCE_ROOT/wine/COPYING.LIB" \
    "$LICENSE_ROOT/Wine-LGPL-2.1-or-later.txt"
install -m 0644 "$REPOSITORY_ROOT/licenses/DXMT-v0.80-LICENSE.txt" \
    "$LICENSE_ROOT/DXMT-MIT.txt"
install -m 0644 "$SOURCE_ROOT/freetype/docs/FTL.TXT" \
    "$LICENSE_ROOT/FreeType-FTL.txt"
install -m 0644 "$SOURCE_ROOT/gnutls/gmp/COPYING.LESSERv3" \
    "$LICENSE_ROOT/GMP-LGPL-3.0-or-later.txt"
install -m 0644 "$SOURCE_ROOT/gnutls/gmp/COPYINGv3" \
    "$LICENSE_ROOT/GMP-GPL-3.0.txt"
install -m 0644 "$SOURCE_ROOT/gnutls/nettle/COPYING.LESSERv3" \
    "$LICENSE_ROOT/Nettle-LGPL-3.0-or-later.txt"
install -m 0644 "$SOURCE_ROOT/gnutls/nettle/COPYINGv3" \
    "$LICENSE_ROOT/Nettle-GPL-3.0.txt"
install -m 0644 "$SOURCE_ROOT/gnutls/gnutls/LICENSE" \
    "$LICENSE_ROOT/GnuTLS-NOTICE.txt"
install -m 0644 "$SOURCE_ROOT/gnutls/gnutls/doc/COPYING.LESSER" \
    "$LICENSE_ROOT/GnuTLS-LGPL-2.1-or-later.txt"
install -m 0644 "$SOURCE_ROOT/gnutls/gnutls/doc/COPYING.LESSER" \
    "$LICENSE_ROOT/libtasn1-LGPL-2.1-or-later.txt"
install -m 0644 "$SOURCE_ROOT/gnutls/gmp/COPYING.LESSERv3" \
    "$LICENSE_ROOT/libunistring-LGPL-3.0-or-later.txt"
install -m 0644 "$SOURCE_ROOT/gnutls/gmp/COPYINGv2" \
    "$LICENSE_ROOT/libunistring-GPL-2.0-or-later.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/capstone/LICENSE.TXT" \
    "$LICENSE_ROOT/Wine-vendored-Capstone-BSD-3-Clause.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/capstone/LICENSE_LLVM.TXT" \
    "$LICENSE_ROOT/Wine-vendored-Capstone-LLVM-NCSA.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/compiler-rt/LICENSE.TXT" \
    "$LICENSE_ROOT/Wine-vendored-compiler-rt-NCSA-or-MIT.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/faudio/LICENSE" \
    "$LICENSE_ROOT/Wine-vendored-FAudio-Zlib.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/fluidsynth/COPYING.md" \
    "$LICENSE_ROOT/Wine-vendored-FluidSynth-LGPL-2.1.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/gsm/COPYRIGHT" \
    "$LICENSE_ROOT/Wine-vendored-GSM-NOTICE.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/jpeg/LICENSE" \
    "$LICENSE_ROOT/Wine-vendored-IJG-JPEG-LICENSE.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/jxr/LICENSE" \
    "$LICENSE_ROOT/Wine-vendored-JPEG-XR-BSD-2-Clause.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/lcms2/COPYING" \
    "$LICENSE_ROOT/Wine-vendored-Little-CMS-MIT.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/ldap/LICENSE" \
    "$LICENSE_ROOT/Wine-vendored-OpenLDAP-2.8.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/ldap/COPYRIGHT" \
    "$LICENSE_ROOT/Wine-vendored-OpenLDAP-COPYRIGHT.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/mpg123/LICENSE" \
    "$LICENSE_ROOT/Wine-vendored-mpg123-LGPL-2.1.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/musl/COPYRIGHT" \
    "$LICENSE_ROOT/Wine-vendored-musl-NOTICE.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/png/LICENSE" \
    "$LICENSE_ROOT/Wine-vendored-libpng-LICENSE.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/tiff/COPYRIGHT" \
    "$LICENSE_ROOT/Wine-vendored-libtiff-LICENSE.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/tomcrypt/LICENSE" \
    "$LICENSE_ROOT/Wine-vendored-LibTomCrypt-LICENSE.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/vkd3d/COPYING" \
    "$LICENSE_ROOT/Wine-vendored-vkd3d-LGPL-2.1-or-later.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/xml2/COPYING" \
    "$LICENSE_ROOT/Wine-vendored-libxml2-MIT.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/xslt/COPYING" \
    "$LICENSE_ROOT/Wine-vendored-libxslt-MIT.txt"
install -m 0644 "$SOURCE_ROOT/wine/libs/zlib/LICENSE" \
    "$LICENSE_ROOT/Wine-vendored-zlib-LICENSE.txt"

echo "Staged runtime notices, licenses, provenance, and SPDX SBOM at $NOTICE_ROOT"
