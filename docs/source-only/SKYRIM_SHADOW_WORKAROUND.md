# Skyrim exterior-shadow workaround

Confirmed: 2026-08-09 through visible gameplay.

## Symptom

A large flat dark patch appeared across terrain and static objects, but not the player. It moved with the camera, grew with camera height or distance, shrank on approach, and eventually left the rendered range.

## Confirmed workaround

Secunda's Skyrim-only `Shadow distance: Off (compatibility)` choice writes:

```ini
[Display]
fShadowDistance=0.0000
```

The patch disappeared in the same gameplay session. This isolates the defect to Skyrim's exterior directional-shadow path. The workaround deliberately disables exterior world shadows; it does not claim to repair the underlying renderer.

Fallout and the shared Wine/DXMT runtime are unchanged.

## Ruled-out experiments

- Ambient occlusion off did not remove the patch.
- Short and long nonzero shadow distances both retained it.
- Changing `fFirstSliceDistance` did not remove it.
- Fog distance changed the night background but not the patch.
- Disabling image-space effects did not remove it.
- Sky/fog toggling relocated the patch; terrain LOD toggling did not affect it.
- `d3d11.sampleNaNToZero=True` did not remove it.

These experiments are not part of the active profile. The saved compatibility choice is the only retained shadow workaround.
