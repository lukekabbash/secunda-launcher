# Source-only implementation plan

## Current milestone

Close the final audio-quality boundary, then harden stability and the distributable runtime without regressing the proven Steam/Skyrim path.

## Next experiment

Measure pre-mute PCM for the exact Skyrim PID through a public CoreAudio process tap. Do not unmute the sleeping user's speakers or request new permissions. If the existing permission boundary rejects the tap, preserve that evidence and leave one explicit human listening check.

## Completed milestones

1. Preserve `main` and establish the `source-only-secunda` branch and contamination fence.
2. Fix the Steam CEF black surface and prove visibly rendered source-only Steam.
3. Backport Wine's Clang syscall-ABI wrappers and prove repeat authenticated Steam connections.
4. Isolate the cloned game data and saves from the known-good installation.
5. Reach rendered gameplay, input, quicksave, exit-code-0 quit, relaunch, and load with live provenance.

## Following milestones

1. Complete unattended PCM or human audible-quality acceptance.
2. Run longer stability, resource-growth, repeat-launch, shader, and frame-pacing probes.
3. Clean-rebuild the runtime for macOS 15, remove absolute build paths, and stage only runtime-required files.
4. Complete notices, licenses, source/relink materials, SPDX relationships, and per-file integrity sealing.
5. Package and audit the runtime-bearing DMG, then re-run Gate 1 and Gate 2 from the signed app on a clean Apple-Silicon Mac.

Every meaningful result is recorded in `STATUS.md` and `GATES.md`.
