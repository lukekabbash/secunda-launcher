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

## Gate 1 — visible source-only Steam: PASS

Date: 2026-08-07

Evidence:

- `gate-1-live-provenance.txt` — visible Steam runtime and library fence.
- `gate-1-logged-in-provenance.txt` — authenticated visible Steam runtime and library fence.
- Three repeat source-only connections reached scheduler success, connection-manager handoff, connection completion, and cached account logon.
- A window-specific capture showed a fully rendered Store UI; it remains uncommitted because it contained local account presentation.
- `patches/wine-secunda-cef-in-process-gpu.patch` fixes the black CEF surface.
- `patches/wine-clang-syscall-abi.patch` fixes the Steam login scheduler hang.

## Gate 2 — Skyrim vertical slice: PASS

Acceptance passed for launcher, menu, non-silent exact-window PCM, input, sustained gameplay, plausible graphics, clone-only quicksave, exit-code-0 quit, relaunch, and load.

Evidence:

- `gate-2-skyrim-vertical-slice.txt` — ordered run/save/quit/relaunch/load record.
- `gate-2-skyrim-provenance.txt` — live game, Steam, Wine server, and mapped-library source-only fence.
- `gate-2-skyrim-audio-coreaudio.json` — active CoreAudio output for 33 of 33 samples.
- `gate-2-skyrim-audio-stack.txt` — loaded XAudio-to-CoreAudio chain from the source runtime.
- `gate-2-skyrim-observability.txt` — redacted window, executable, library, CPU, RSS, and contamination evidence.
- Exact-window audio probe — 8.08 seconds, 69.6% non-silent samples, -51.54 dBFS RMS, -31.83 dBFS peak, and no clipping.
- Final packaged one-click regression — rendered menu, loaded-save gameplay, movement and camera input, duplicate-Play rejection, and clean complete shutdown.

The user also previously confirmed audible game output. Automation never changed speaker mute state.

## Gate 3 — performance and stability: PASS WITH HOST LIMITATION

Repeated launches, save/load, duplicate prevention, and complete shutdown passed. Ten gameplay samples showed stable short-run RSS near 805 MiB. At 1440x900, cadence measured about 32.2 fps and roughly 15 ms of GPU time; present interval averaged 31.02 ms with a 36.16 ms P95. macOS Low Power Mode was enabled on AC power and is now reported by the launcher without being changed. One older synthetic journal-key experiment produced `0xC0000005` and remains a historical stability datapoint.

## Gate 4 — free distribution: IN PROGRESS

The source runtime has been rebuilt for macOS 15. The packaged app passes relocation, exact file/link/mode integrity, proprietary-payload exclusion, deep signing, notices, provenance, SPDX, cold one-click Play, complete-stop acceptance, and blank-home prefix creation that advances automatically to Steam installation. The explicit TEST-ONLY DMG passes checksum, read-only mount, source-complete package audit, mounted-app self-check, and mounted blank-home preparation. Developer ID signing/notarization and quarantined acceptance on a separate clean Apple-Silicon Mac remain before this gate can be called recipient-ready.
