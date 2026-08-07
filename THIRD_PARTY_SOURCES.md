# Third-party source inventory

The local `sources/` directory was extracted from `crossover-sources-26.3.0.tar.gz` and is intentionally excluded from Git. The archive is used as a source-compliance input: Secunda builds its own Wine 11.0 runtime from the included Wine and dependency sources; it does not contain or authorize use of the proprietary CrossOver application runtime.

The Direct3D 11 bridge is open-source DXMT v0.80 from the [official tagged release](https://github.com/3Shain/dxmt/releases/tag/v0.80). The build verifies SHA-256 `8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d` before staging it. Its MIT license is stored at `licenses/DXMT-v0.80-LICENSE.txt`.

The Direct3D 9 Vulkan path uses MoltenVK v1.4.2 (Apache-2.0, [official release](https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.2), SHA-256 `f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e`) and DXVK v1.10.3's d3d9 (Zlib, [official release](https://github.com/doitsujin/dxvk/releases/tag/v1.10.3), SHA-256 `8d1a3c912761b450c879f98478ae64f6f6639e40ce6848170a0f6b8596fd53c6`), staged by `scripts/fetch-vulkan-stack.sh` with licenses at `licenses/MoltenVK-v1.4.2-LICENSE.txt` and `licenses/DXVK-v1.10.3-LICENSE.txt`. Games opt into DXVK per title; Wine's builtin GL path remains the default for Direct3D 9.

The runtime also builds FreeType 2.13.3, GMP 6.3.0, Nettle 3.10, and GnuTLS 3.8.3 from pinned source inputs. Wine's statically included component sources and their licenses are enumerated in `packaging/runtime-provenance.json`, `packaging/runtime-sbom.spdx.json`, and `packaging/THIRD_PARTY_NOTICES.txt`.

The packaging pipeline stages component license texts, runtime provenance, an SPDX SBOM, a per-file integrity manifest, the exact supplied source archive, the verified Nettle archive, Secunda's Wine patches, and the runtime build scripts. The mounted-DMG verifier checks that those materials accompany the binary runtime.

Secunda never bundles CrossOver.app, D3DMetal, GPTK, `d3dshared`, Steam, Skyrim, a managed prefix, account data, sessions, saves, or diagnostic logs. Players obtain Steam directly from Valve and install their own licensed game through Steam.
