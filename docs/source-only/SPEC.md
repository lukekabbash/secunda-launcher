# Secunda source-only runtime

## Objective

Ship a free Apple-silicon Skyrim launcher whose complete compatibility path is owned by Secunda and built from redistributable source.

`Secunda.app -> source-built Wine/DXMT runtime -> isolated prefix -> Windows Steam -> Skyrim Special Edition -> macOS Metal`

## Hard constraints

- Never discover, execute, link, load, copy, or redistribute a proprietary compatibility runtime.
- Preserve the working `main` branch, the existing `SkyrimSE-CrossOver` bottle, credentials, saves, and game files.
- All acceptance runs use the isolated `SkyrimSE` prefix and record executable plus loaded-library provenance.
- Steam authentication remains entirely inside Steam. Secunda never asks for or records credentials.
- Game files and account data are not part of the distributable.

## Acceptance gates

1. The launcher cannot fall back to a forbidden runtime; automated provenance checks pass.
2. Source-only Steam is visibly rendered and interactive.
3. Skyrim reaches sustained 3D gameplay with correct graphics, audio, and keyboard/mouse input.
4. A save is created or loaded, the game quits cleanly, relaunches, and loads that save.
5. Repeated-launch, memory, shader, frame-pacing, crash, graphics, and audio evidence is captured.
6. A free-runtime DMG passes integrity, licensing, contamination, and clean-machine setup checks.

Process existence alone never satisfies a visual or gameplay gate.
