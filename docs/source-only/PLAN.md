# Source-only implementation plan

## Current milestone

The local source-only implementation and test-only package are validated. The remaining milestone is trusted distribution and acceptance on a separate clean Apple-Silicon Mac.

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
11. Prove packaged first-run preparation under a blank home automatically advances to Steam installation after complete Wine initialization.
12. Publish an explicit TEST-ONLY ad-hoc DMG and verify its checksum, mounted app, corresponding-source payload, and blank-home preparation flow.

## Remaining distribution milestones

1. Supply Developer ID credentials and sign and notarize a recipient candidate.
2. On a separate clean Apple-Silicon Mac, verify quarantined installation, first-run Steam login, game download/detection, Play, audio/input/gameplay, save/load, Stop, and uninstall boundaries.

Every meaningful result is recorded in `STATUS.md` and `GATES.md`.
