# Source-only acceptance gates

## Gate 0 — source-only fence: PASS

Date: 2026-08-06

Evidence:

- `./scripts/verify.sh` — Swift build completed; launcher and contamination contracts passed.
- `./scripts/test-source-only-provenance.sh` — 10 contamination contracts passed.
- `SECUNDA_SOURCE_ONLY=1 ./scripts/verify-source-only-provenance.sh --runtime Runtime/wine/bin/wine` — source runtime preflight passed.
- Runtime lookup contains only bundled, repository source-build, or manifest-bearing development candidates.
- CrossOver runtime locator, bottle creation, user-facing acquisition link, and external library-path inheritance were removed from this branch.

This gate proves the fence and preflight only. It does not claim a live Steam or Skyrim process has passed loaded-library inspection.

## Gate 1 — visible source-only Steam: IN PROGRESS

Known failure: DXMT returns `E_FAIL` for CEF's cross-process window swapchain; Steam reports `EGL_BAD_ALLOC` and renders black.

Next test: `-cef-in-process-gpu`, with live PID/library provenance and visual inspection.

## Gate 2 — Skyrim vertical slice: NOT RUN

Required: launcher, menu, audio, input, sustained gameplay, plausible graphics, save, quit, relaunch, load.

## Gate 3 — performance and stability: NOT RUN

Required: repeated launches, crash/memory/shader/frame-pacing/graphics/audio evidence.

## Gate 4 — free distribution: NOT RUN

Required: relocatable runtime, full licenses/notices/source provenance, file checksums, integrity checks, clean uninstall boundary, clean-Mac procedure, and audited DMG.
