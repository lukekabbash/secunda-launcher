# Source-only status

Updated: 2026-08-07

## Latest known-good state

- Branch: `source-only-secunda`; `main` remains at `ad1ef70`.
- Distributable runtime: x86-64 Wine 11.0 under Rosetta with DXMT 0.80 at `Runtime/wine-macos15`.
- Acceptance prefix: the private APFS clone `SkyrimSE-SourceClone`; its game data, profile, and saves do not mutate the known-working baseline.
- Gate 0 passed: runtime discovery, child environments, executable paths, runtime integrity, and package audits reject proprietary fallback or contamination.
- Gate 1 passed: the source-only runtime renders a usable Windows Steam UI and completes Steam authorization.
- Gate 2 passed: the source-only path renders the launcher and menu, produces non-silent audio, accepts keyboard/mouse input, enters sustained gameplay, saves, quits, relaunches, and loads the save.
- The packaged one-click path now advances through five truthful stages, detects only the exact target Windows processes, starts Skyrim after Steam authorization, and confirms that the game stays running.
- The final packaged regression reached a correctly rendered 1440x900 menu, loaded the existing save into gameplay, accepted movement and camera input, rejected a duplicate Play request, and cleanly stopped Skyrim, Steam, and the Wine server.
- A packaged-app first-run test under a blank temporary home created a new prefix, waited for Wine initialization to settle, and advanced directly to `Install Steam` without a manual Refresh.
- Interactive Steam/game output is discarded. The legacy `steam-launch.log` retained the exact same size and modification time across the packaged regression.
- Exact-window ScreenCaptureKit audio acceptance measured 8.08 seconds of PCM, 69.6% non-silent samples, -51.54 dBFS RMS, -31.83 dBFS peak, and no clipping. The speakers were never unmuted by automation.
- The launcher self-check passes 84 contracts; the no-execution Skyrim readiness suite passes 37 contracts.
- The bundled app audit covers 3,733 runtime files, 12 symlinks, 3,765 modes, 42 Mach-O workers, a macOS 15.0 floor, deep code signing, relocatability, notices, provenance, and SPDX metadata.

## Accepted runtime and launcher fixes

- Steam's embedded browser GPU work runs in-process, avoiding an unsupported cross-process window swapchain.
- Wine's Clang syscall-ABI wrappers are backported to the supplied Wine 11.0 layout, fixing the prior Steam login scheduler loop.
- `WINEMSYNC=1` uses the supplied source synchronization path.
- XAudio and X3DAudio use Wine's built-in implementations through the source-only prefix.
- Child processes receive a small host-variable allowlist; credential, loader, and foreign-runtime variables are removed.
- Process capture uses a bounded nonblocking dispatch source, finishes on the exact foreground process, and does not wait for inherited background pipe handles.
- Windows process checks use filtered `tasklist` queries for only `SkyrimSE.exe` and `SkyrimSELauncher.exe`.
- Install readiness requires completed Steam state, a plausible contained PE executable, and baseline game data before Play becomes available.
- Fresh-prefix preparation waits for the bundled Wine server to finish initialization before selecting the private Windows user directory or reporting success.

## Performance and stability

- Windowed 1920x1080 cadence measured about 28.2 fps; 1440x900 measured about 32.2 fps.
- At 1440x900, the measured present interval averaged 31.02 ms with a 36.16 ms P95. Disabling the game's sync interval was slightly worse, so the stable setting remains enabled.
- Metal HUD inspection measured roughly 15 ms of GPU work while macOS reported Low Power Mode enabled on AC power. The launcher now reports that host limitation but never changes the global setting.
- Short-run gameplay RSS stayed near 805 MiB with a 0.6 MiB range. Repeated launch, save/load, and clean-stop runs passed.

## Current caveats

- The current app is ad-hoc signed for local testing. A recipient-ready release still requires Developer ID signing, notarization, and quarantined clean-Mac acceptance.
- The app declares Game Mode eligibility, but the live translated child still showed Game Mode off in the measured HUD. Do not claim active Game Mode until macOS reports it.
- One older synthetic journal-key experiment ended with `0xC0000005`; later normal gameplay/save/load/quit cycles remained stable. Preserve this as a historical stability datapoint.
- The final local DMG is intentionally labeled TEST-ONLY unless signing/notarization credentials are supplied.

## Next action

1. Rebuild the explicit test-only DMG from the first-run fix and verify its mounted app, checksum, corresponding-source inventory, and blank-home preparation flow locally.
2. For broad sharing, sign and notarize the same candidate and run a quarantined clean-Apple-Silicon install/login/download/play test.
