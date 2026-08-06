# Secunda acceptance run

## Automated gates

- `./scripts/verify.sh` passes all launcher-core contracts.
- `swift build -c release` passes.
- The packaged app passes `codesign --verify --deep --strict`.
- Runtime discovery identifies either the complete external Apple-silicon engine or the executable bundled fallback.
- `./scripts/smoke-test-runtime.sh` boots Windows and creates a Direct3D 11.1 device through Metal.
- Every managed path resolves beneath `~/Library/Application Support/Secunda Launcher`.

## Steam handoff

- A fresh bottle initializes without an existing Wine prefix.
- SteamSetup is downloaded from Valve over HTTPS.
- Secunda's Open Steam action opens Steam's own visible login surface.
- Secunda never receives or stores credentials.
- Steam restarts and self-updates successfully.
- Skyrim Special Edition can be installed or discovered.

## Gameplay pass

- The launcher reaches Skyrim's main menu.
- New game reaches the end of the Helgen intro without a crash.
- Music, voices, effects, and ambient audio are present without sustained crackle.
- Mouse and keyboard work; controller is detected when connected.
- No black or missing textures appear.
- Frame pacing is playable without sustained presentation hitching.
- A new save survives quit and relaunch.
- Steam Cloud status is checked after the local save exists.

## Recovery pass

- Save backup produces a separate dated copy.
- Steam file verification opens for app 489830.
- Logs identify runtime, bottle, Steam, and game launch failures.
- Removing Secunda data, when implemented, cannot target anything outside Secunda's managed root.

## Recipient handoff pass

- The share DMG contains only Secunda Launcher, an Applications shortcut, and the setup guide.
- The share build contains no fallback runtime, CrossOver app, Steam client, game files, bottle, logs, saves, or account data.
- The DMG passes `hdiutil verify`, and its SHA-256 companion file matches.
- A recipient with their own Apple-silicon Mac, CrossOver installation, Steam account, and game ownership can complete first-run setup without a runtime picker.
- A production handoff uses Developer ID signing plus Apple notarization; an ad-hoc build is labeled as a testing artifact.
