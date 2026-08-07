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

## Gate 2 — Skyrim vertical slice: IN PROGRESS

Automated acceptance passed for launcher, menu, input, sustained gameplay, plausible graphics, clone-only quicksave, exit-code-0 quit, relaunch, and load.

Evidence:

- `gate-2-skyrim-vertical-slice.txt` — ordered run/save/quit/relaunch/load record.
- `gate-2-skyrim-provenance.txt` — live game, Steam, Wine server, and mapped-library source-only fence.
- `gate-2-skyrim-audio-coreaudio.json` — active CoreAudio output for 33 of 33 samples.
- `gate-2-skyrim-audio-stack.txt` — loaded XAudio-to-CoreAudio chain from the source runtime.
- `gate-2-skyrim-observability.txt` — redacted window, executable, library, CPU, RSS, and contamination evidence.

Remaining requirement: prove non-silent PCM before endpoint mute or perform one unmuted human listening check for audible sound, crackle, and dropouts. The speakers were intentionally left muted during unattended work.

## Gate 3 — performance and stability: IN PROGRESS

Three game launches completed; two later runs loaded the refreshed save and exited with code 0. One earlier synthetic journal-key experiment produced `0xC0000005` and remains an open stability datapoint. Ten gameplay samples showed stable short-run RSS. Longer duration, frame-pacing/shader behavior, and repeated unattended launches remain.

## Gate 4 — free distribution: IN PROGRESS

Packaging, SBOM, source bundle, runtime-integrity, relocation, and mounted-DMG verification are under implementation. A clean rebuild and clean-Mac acceptance remain mandatory before pass.
