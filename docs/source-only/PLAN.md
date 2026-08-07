# Source-only implementation plan

## Current milestone

Freeze the validated one-click source-only app, produce and mount-verify an explicit test-only DMG, then checkpoint the implementation.

## Completed milestones

1. Preserve `main`; establish the `source-only-secunda` branch and contamination fence.
2. Fix the Steam embedded-browser surface and prove visibly rendered source-only Steam.
3. Backport the Wine syscall-ABI wrappers and prove repeat Steam connections.
4. Isolate cloned game data, profiles, and saves from the known-working installation.
5. Prove graphics, exact-window non-silent audio, input, gameplay, save, quit, relaunch, and load.
6. Measure cadence, memory, GPU time, sync behavior, and the active host Low Power Mode constraint without reducing visual fidelity.
7. Build the macOS-15 source runtime, relocate it, seal exact file/link/mode integrity, and stage licenses, provenance, and SPDX data.
8. Implement five-stage one-click Play, bounded targeted Windows-process detection, duplicate protection, private interactive output, and clean Stop.
9. Pass the packaged cold-start, menu, loaded-save gameplay, input, duplicate-Play, and complete-stop regression.
10. Harden static readiness and its synthetic no-execution/non-mutation suite to 37 contracts.

## Remaining distribution milestones

1. Produce the explicit TEST-ONLY ad-hoc DMG and verify the mounted app and corresponding-source archive.
2. Create the validated Git checkpoint.
3. Supply Developer ID credentials, sign and notarize a recipient candidate, then test a quarantined clean-Mac install.
4. On a clean recipient Mac, verify first-run Steam login, game download/detection, Play, audio/input/gameplay, save/load, Stop, and uninstall boundaries.

Every meaningful result is recorded in `STATUS.md` and `GATES.md`.
