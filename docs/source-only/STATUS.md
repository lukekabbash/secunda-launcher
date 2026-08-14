# Source-only status

Updated: 2026-08-09

## Latest known-good state

- Branch: `source-only-secunda`; `main` remains at `ad1ef70`.
- Distributable runtime: x86-64 Wine 11.0 under Rosetta with DXMT 0.80 at `Runtime/wine`.
- Acceptance prefix: the private APFS clone `SkyrimSE-SourceClone`; its game data, profile, and saves do not mutate the known-working baseline.
- Gate 0 passed: runtime discovery, child environments, executable paths, runtime integrity, and package audits reject proprietary fallback or contamination.
- Gate 1 passed: the source-only runtime renders a usable Windows Steam UI and completes Steam authorization.
- Gate 2 passed: the source-only path renders the launcher and menu, produces non-silent audio, accepts keyboard/mouse input, enters sustained gameplay, saves, quits, relaunches, and loads the save.
- The packaged one-click path now advances through five truthful stages, detects only the exact target Windows processes, starts Skyrim after Steam authorization, and confirms that the game stays running.
- The final packaged regression reached a correctly rendered 1440x900 menu, loaded the existing save into gameplay, accepted movement and camera input, rejected a duplicate Play request, and cleanly stopped Skyrim, Steam, and the Wine server.
- A packaged-app first-run test under a blank temporary home created a new prefix, waited for Wine initialization to settle, and advanced directly to `Install Steam` without a manual Refresh.
- The rebuilt `Secunda Launcher-0.1.0-TEST-ONLY.dmg` passed SHA-256 verification, read-only mounting, mounted-app self-check, source/runtime/package audits, and a second blank-home preparation test from the mounted copy.
- Interactive Steam/game output is discarded by default. Diagnostic mode writes separate Steam and per-game launch logs; those raw logs stay outside the redacted support excerpt.
- Exact-window ScreenCaptureKit audio acceptance measured 8.08 seconds of PCM, 69.6% non-silent samples, -51.54 dBFS RMS, -31.83 dBFS peak, and no clipping. The speakers were never unmuted by automation.
- The launcher self-check passes 200 contracts; the no-execution Skyrim readiness suite passes 37 contracts.
- The current packaged runtime audit covers 3,742 files, 12 symlinks, 3,777 modes, 45 Mach-O workers, a macOS 15.0 floor, relocatability, notices, provenance, SPDX metadata, and proprietary/user-payload exclusion.

## Accepted runtime and launcher fixes

- Steam's embedded browser GPU work runs in-process, avoiding an unsupported cross-process window swapchain.
- Wine's Clang syscall-ABI wrappers are backported to the supplied Wine 11.0 layout, fixing the prior Steam login scheduler loop.
- `WINEMSYNC=1` uses the supplied source synchronization path.
- XAudio and X3DAudio use Wine's built-in implementations through the source-only prefix.
- Child processes receive a small host-variable allowlist; credential, loader, and foreign-runtime variables are removed.
- Process capture uses a bounded nonblocking dispatch source, finishes on the exact foreground process, and does not wait for inherited background pipe handles.
- Windows process checks use filtered `tasklist` queries for each descriptor's exact game and launcher images, including independent 32/64-bit aliases where a game ships both.
- Install readiness requires completed Steam state, a plausible contained PE executable, and baseline game data before Play becomes available.
- Fresh-prefix preparation waits for the bundled Wine server to finish initialization before selecting the private Windows user directory or reporting success.
- Game launch succeeds only after the exact Windows executable survives a ten-second health window; a transient process now reports a failed start instead of a false success.
- Fast synchronization changes are transactional: the requested mode is queued while Wine/Steam is active and becomes the runtime mode only after a clean, quiet boundary.
- Every session's launch environment is stamped as `SECUNDA_SESSION_FINGERPRINT`; before handing a game to a warm Steam, the launcher reads the live wineserver's stamp from the host kernel and cold-restarts the game space when the stamp is missing or different. Instrumented or experimental sessions can never serve later game launches.
- Steam keeps a title-neutral environment. Per-title environment overrides are reserved for direct game processes rather than leaking through a long-lived Steam client.
- The redistributable voice-audio repair is restricted to titles that need it rather than mutating every supported bottle.
- Runtime smoke testing now covers both 64-bit and 32-bit Direct3D 11 through the bundled Metal path.
- Insurgency now uses Source's live `insurgency/cfg/video.txt`: Secunda skips the startup video, writes the existing fullscreen/borderless/resolution/VSync keys, and launches a native point-space borderless surface so the old exclusive path cannot leave a black screen. It remains a catalog profile until a fresh rendered-menu, input, audio, gameplay, and clean-stop pass is recorded.
- Supreme Commander 2 preserves the `/windowed W H` bootstrap required to reach engine initialization. Borderless sessions switch to native point-space full-display dimensions and an app-scoped undecorated Mac-driver surface; ordinary windowed sessions retain the requested client size. Secunda writes only an already-present `UnitCap` key and leaves the game's adapter, window placement, and graphics tables alone.
- Angels Fall First retains the launch tuple that reached sustained gameplay (`-SEEKFREELOADING -DX9 -windowed`) but exposes no unaccepted display, FOV, or quality settings and writes none of its installed INI files.
- Diagnostic launches append a credential-free JSONL record containing the exact game arguments, display tuple, DPI, Retina mode, renderer, and pre-launch engine-log timestamp/size. Detailed Wine output remains separate, and native SC2/AFF engine logs stay game-owned.
- These profile changes are code contracts, not rendered-gameplay acceptance. Insurgency's prior black/fullscreen sessions and Supreme Commander 2 still require fresh menu, input, audio, gameplay, settings, and clean-stop checks from the rebuilt package.
- Launch health accepts raised game windows: Wine's Mac driver lifts fullscreen and screen-covering borderless windows above the menu bar, so requiring layer 0 misreported healthy sessions as windowless. Only sub-desktop layers are disqualifying.
- The Running Processes panel now sees the whole game space: any process whose command line references a managed bottle, plus any process whose executable lives inside a Secunda source runtime, identified by the provenance manifest every runtime carries. Leftover Wine workers from a packaged copy or a source-tree test runtime were previously invisible and unkillable from Settings.
- Skyrim's title-only `Shadow distance: Off (compatibility)` profile writes `fShadowDistance=0`. A visible gameplay test confirmed that it removes the camera-relative dark terrain/static-object patch; it does so by disabling exterior directional shadows and is a bounded workaround, not a restored-shadow renderer fix. The diagnostic record and rollback path are in `SKYRIM_SHADOW_WORKAROUND.md`.

## Black Ops II extension status

- Multiplayer (`202990`) and Zombies (`212910`) each survived a fresh 60-second process-health run using the cleaned source runtime and the original authenticated Steam prefix.
- Both modes loaded the runtime's 32-bit `d3d11.dll`, `dxgi.dll`, `winemetal.dll`, the matching 64-bit `winemetal.so`, Apple's Metal driver, and the installed game's own `steam_api.dll`.
- This proves Steam authorization, sustained process execution, and the intended PE32 Direct3D 11-to-Metal ownership path. It does **not** yet prove rendered menus, audio, input, online services, matchmaking, or gameplay because the Mac was locked during the unattended run.
- Campaign (`202970`) completes Steam's executable-generation exchange, starts, and then exits after roughly three seconds with Windows status `0xC0000008` (`STATUS_INVALID_HANDLE`). A fully restarted fast-synchronization-off run failed the same way.
- The remaining campaign boundary is below Secunda's launch orchestration: translated x86 execution accepts execute breakpoints, but Wine cannot set the data-watchpoint state this executable requests under the current Rosetta path. A page-protection experiment was too coarse and all temporary runtime instrumentation was removed; the staged source matches the official CodeWeavers source again.
- Secunda does not patch, decrypt, replace, or bypass Steam-generated executables. Campaign should remain a partial compatibility result until the translated runtime has correct data-watchpoint/debug-context semantics.

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
- Black Ops II Multiplayer and Zombies still need an unlocked visual/audio/input/online acceptance pass. Campaign is not currently playable on this Rosetta-based runtime.

## Next action

1. Manually run the new Insurgency, Supreme Commander, Forged Alliance, Angels Fall First, and Battlefront II Classic profiles through rendered-menu, audio, input, gameplay, settings, and clean-stop acceptance before making compatibility claims.
2. On the current unlocked Mac, run Black Ops II Multiplayer and Zombies through rendered-menu, audio, keyboard/mouse/controller, online-service, matchmaking/private-match, gameplay, and clean-stop acceptance.
3. Revisit Campaign only when the translated runtime can preserve the requested x86 data-watchpoint/debug-context state; do not substitute an executable or DRM bypass.
4. For broad sharing, sign and notarize the validated candidate with a Developer ID identity.
5. Run the notarized, quarantined candidate through first-run Steam login, game download, Play, audio/input/gameplay, save/load, Stop, and uninstall acceptance on a separate clean Apple-Silicon Mac.
