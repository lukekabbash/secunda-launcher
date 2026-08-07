# Secunda acceptance contract

The concise live status is in `source-only/GATES.md`. This file defines what a release candidate must prove; unchecked work is not implied to have passed.

## Source-only fence

- The launcher selects only a bundled or repository source runtime with valid provenance.
- No executable, mapped library, loader override, or child process references CrossOver.app, D3DMetal, GPTK, `d3dshared`, or another proprietary compatibility payload.
- Child environments are allowlisted and do not inherit developer tokens, credential sockets, or foreign loader paths.
- Every live Steam and Skyrim run records the exact executable and mapped-library provenance.

## Steam handoff

- A fresh, private managed prefix initializes without an existing Wine prefix.
- SteamSetup downloads directly from Valve over HTTPS.
- Steam renders a visibly usable login/store/library interface rather than a black surface.
- Authentication remains entirely within Steam; Secunda neither receives nor stores credentials.
- Steam reconnects after a clean source-runtime restart and can install or detect Skyrim Special Edition.

## Skyrim vertical slice

- Secunda launches Skyrim through Steam app 489830.
- The launcher, main menu, and sustained 3D gameplay render plausibly through DXMT/Metal.
- Music/effects/voices reach CoreAudio without sustained silence, crackle, or dropouts.
- Keyboard movement and actual mouse camera input work.
- A save is created or refreshed only in the private Secunda prefix.
- The game quits cleanly, relaunches, and loads that save.
- The acceptance run passes the source-only provenance fence while the game is live.

## Performance and stability

- Startup and repeated-launch outcomes are recorded, including every abnormal exit.
- Present cadence, long-frame counts, shader compilation/cache behavior, CPU, and memory are measured during gameplay.
- A bounded soak shows no pathological memory growth, major rendering corruption, sustained presentation hitching, or recurring crash.
- Performance evidence is captured without storing window titles, account data, raw audio, command lines, or process environments.

## Recipient handoff

- The mounted DMG contains Secunda.app, its source runtime, an Applications shortcut, recipient instructions, notices, SPDX SBOM, integrity hashes, build scripts, patches, and corresponding source.
- It contains no Steam client, Skyrim files, prefix, session, credentials, saves, logs, CrossOver app, D3DMetal, GPTK, or other proprietary runtime payload.
- Runtime Mach-O files are x86-64, target macOS 15 or earlier, and contain only relocatable or system library paths.
- App, runtime, source bundle, and DMG checksum verifiers pass after mounting the final artifact read-only.
- A clean Apple-silicon Mac can install the DMG, create its prefix, log into Steam, install Skyrim, and repeat the complete vertical slice.
- Developer ID signing/notarization is a publisher trust step, not a paid compatibility-runtime dependency; ad-hoc artifacts are labeled as local testing builds.

## Recovery boundary

- Save backup produces a separate dated copy.
- Steam file verification opens for app 489830.
- Logs identify actionable runtime, prefix, Steam, and game launch failures.
- Any cleanup or uninstall action resolves and names an exact target beneath Secunda's managed application-support root before changing data.
