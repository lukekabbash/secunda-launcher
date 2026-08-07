# Source-only implementation plan

## Current milestone

Make Steam CEF present through DXMT without a cross-process swapchain.

## Next experiment

Launch the existing isolated source prefix with `-cef-in-process-gpu` plus the current compositor flags. Confirm the helper command line, renderer, disappearance of `E_FAIL`/`EGL_BAD_ALLOC`, loaded-library provenance, and visible interactivity.

## Following milestones

1. Clone or expose the already owned Skyrim files to the isolated source prefix without mutating the working bottle.
2. Run and repair the graphics/audio/input/gameplay/save-reload vertical slice.
3. Measure repeatability and performance.
4. Make the runtime relocatable, deterministic, licensed, integrity-checked, and packageable.

Every meaningful result is recorded in `STATUS.md` and `GATES.md`.
