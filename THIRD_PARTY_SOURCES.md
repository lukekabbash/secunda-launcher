# Third-party source inventory

The local `sources/` directory was extracted from `crossover-sources-26.3.0.tar.gz` and is intentionally excluded from Git. The archive is used as a source-compliance input: Secunda builds its own Wine 11.0 runtime from the included Wine and dependency sources; it does not contain or authorize use of the proprietary CrossOver application runtime.

The Direct3D 11 bridge is open-source DXMT v0.80 from the [official tagged release](https://github.com/3Shain/dxmt/releases/tag/v0.80). The build verifies SHA-256 `8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d` before staging it. Its MIT license is stored at `licenses/DXMT-v0.80-LICENSE.txt`.

The runtime also builds FreeType 2.13.3, GMP 6.3.0, Nettle 3.10, and GnuTLS 3.8.3 from pinned source inputs. Wine's statically included component sources and their licenses are enumerated in `packaging/runtime-provenance.json`, `packaging/runtime-sbom.spdx.json`, and `packaging/THIRD_PARTY_NOTICES.txt`.

The packaging pipeline stages component license texts, runtime provenance, an SPDX SBOM, a per-file integrity manifest, the exact supplied source archive, the verified Nettle archive, Secunda's Wine patches, and the runtime build scripts. The mounted-DMG verifier checks that those materials accompany the binary runtime.

Secunda never bundles CrossOver.app, D3DMetal, GPTK, `d3dshared`, Steam, Skyrim, a managed prefix, account data, sessions, saves, or diagnostic logs. Players obtain Steam directly from Valve and install their own licensed game through Steam.
