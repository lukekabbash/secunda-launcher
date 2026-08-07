# Gate 3 frame and shader instrumentation

## What this measures

The primary probe uses Apple’s Metal Performance HUD logging for the exact
source-only Skyrim process. It records per-frame present interval and GPU time,
then reduces those events to counts, averages, percentiles, and frame-budget
overruns. Raw unified-log events and shader names never enter the report.

This is the authoritative Gate 3 frame-pacing path. Apple defines HUD frame
interval as the on-glass interval between consecutive Metal drawables and GPU
time from the command buffers scheduled for each frame.

The report also embeds the exact macOS window identity and the existing
source-only executable/mapped-library provenance. A successful data capture is
not by itself a performance pass; judge the numbers against the target frame
budget and preserve the scene, resolution, and settings used for comparison.

## Primary launch mode

Add these variables only to the bounded performance launch:

```text
MTL_HUD_ENABLED=1
MTL_HUD_LOG_ENABLED=1
MTL_HUD_OPACITY=0.0
```

The first two variables enable Apple’s per-frame Metal telemetry. Opacity zero
hides the visual overlay while leaving logging enabled. Do not enable encoder
timing for the baseline run; Apple notes that its additional processing can
increase HUD CPU cost.

During visibly active gameplay, capture 30 seconds:

```sh
SECUNDA_SOURCE_ONLY=1 ./scripts/capture-metal-performance.sh \
  --runtime Runtime/wine/bin/wine \
  --pid <SKYRIM_PID> \
  --window-id <SKYRIM_WINDOW_ID> \
  --duration 30 \
  --target-fps 60 \
  --shader-cache-dir "$HOME/Library/Application Support/Secunda Launcher/Caches/Graphics" \
  --metal-cache-dir "$(getconf DARWIN_USER_CACHE_DIR)dxmt/SkyrimSE.exe/com.apple.metal" \
  --report docs/source-only/evidence/gate-3-metal-performance.txt
```

The two cache roots are optional. Only aggregate file counts, bytes, and newest
modification time are recorded; paths and cache contents are not.

Interpret the key fields as follows:

- `PRESENT_INTERVAL_MS_P95` and `P99` expose sustained tail pacing.
- `PRESENT_OVER_1_5X_BUDGET`, `2X`, and `3X` count increasingly large misses
  relative to the explicit target, without inventing a universal pass line.
- `GPU_TIME_MS_*` distinguishes GPU-bound frames from presentation or CPU-side
  delays.
- `FRAME_DATA_RESULT=PASS` means valid telemetry arrived, not that performance
  passed.

## Shader-cache characterization

Use a separate run with the same save, camera, settings, and traversal. Add:

```text
MTL_HUD_LOG_SHADER_ENABLED=1
```

Run that route twice without clearing either cache. Compare
`SHADER_CACHE_HITS`, `SHADER_CACHE_MISSES`, the raw reported compilation-time
aggregates, and the before/after cache sizes. Shader logging emits an event for
each compilation, so its run is cache evidence rather than the clean frame-time
benchmark.

DXMT 0.80 maintains its own `shaders_<metal-version>.db` when
`DXMT_SHADER_CACHE` is not disabled, honors the existing
`DXMT_SHADER_CACHE_PATH`, and separately assigns a Metal pipeline-cache folder.
The probe observes both layers without opening or changing their contents.

## Existing-process fallback

If the current game was not launched with Metal HUD variables, the bounded
fallback can still sample one exact window:

```sh
SECUNDA_SOURCE_ONLY=1 ./scripts/capture-window-cadence.sh \
  --runtime Runtime/wine/bin/wine \
  --pid <SKYRIM_PID> \
  --window-id <SKYRIM_WINDOW_ID> \
  --duration 15 \
  --target-fps 60 \
  --report docs/source-only/evidence/gate-3-window-cadence.txt
```

This ScreenCaptureKit sampler saves no pixels. It measures compositor delivery
and low-resolution visual changes, so it must run during clearly moving
gameplay. It cannot report GPU time, cannot distinguish a genuinely static scene
from a stalled renderer, may require Screen Recording permission, and must not
be presented as exact Metal frame timing.

## Verification

```sh
./scripts/test-gate-performance.sh
```

The deterministic suite checks both Swift reducers, exact-PID filtering,
privacy redaction, wrapper syntax, and the primary/fallback limitation language.
Live acceptance still requires a real moving Skyrim window.

## Primary references

- [Apple: Monitoring your Metal app’s graphics performance](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance/)
- [Apple: Customizing the Metal Performance HUD](https://developer.apple.com/documentation/xcode/customizing-metal-performance-hud)
- [Apple: Understanding Metal Performance HUD metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics)
- [Apple: ScreenCaptureKit frame metadata](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo)
- [DXMT 0.80 shader-cache implementation](https://github.com/3Shain/dxmt/blob/v0.80/src/dxmt/dxmt_shader_cache.cpp)
- [DXMT 0.80 Metal pipeline-cache setup](https://github.com/3Shain/dxmt/blob/v0.80/src/dxgi/dxgi.cpp)
