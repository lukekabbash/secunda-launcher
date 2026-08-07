# Source-only status

Updated: 2026-08-06

## Latest known-good state

- Branch: `source-only-secunda`; `main` remains at `ad1ef70`.
- Source runtime: x86-64 Wine 11.0 under Rosetta with DXMT 0.80, located at `Runtime/wine`.
- Source prefix: `~/Library/Application Support/Secunda Launcher/Bottles/SkyrimSE`.
- The launcher no longer contains runtime discovery or bottle paths for the proprietary baseline.
- Parent loader variables are scrubbed before every child launch.
- Runtime discovery requires a parsed source-runtime provenance manifest.
- Swift self-check: source-runtime and launcher contracts passed.
- Standalone contamination suite: 10 contracts passed.

## Current observed failure

Steam CEF reaches ANGLE D3D11 on the Apple M5, then DXMT 0.80 rejects `CreateSwapChainForHwnd` because the GPU helper process does not own the browser process's window. The resulting `E_FAIL` becomes `EGL_BAD_ALLOC`, producing the black UI.

## Decision

Test CEF's in-process GPU mode before modifying DXMT. It directly removes the observed cross-process boundary while preserving the working D3D11/Metal path.

## Known packaging debt

- Existing runtime binaries carry absolute build-prefix RPATH entries and are not yet fresh-machine clean.
- Packaging does not yet copy the full third-party license/notice set or a per-file integrity manifest.
- The project owner must choose Secunda's own source license before public redistribution.
