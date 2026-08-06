# Secunda Launcher

A focused, unofficial macOS launcher for running a separately owned Steam copy of Skyrim Special Edition inside one isolated compatibility bottle.

## Current development run

Requirements: macOS 14 or newer on Apple silicon, Rosetta 2, and the Swift toolchain included with Xcode Command Line Tools. The Secunda interface builds natively for Apple silicon. Its Windows worker is x86_64 because Steam and Skyrim are x86 Windows applications; Rosetta translates only that worker.

```sh
./scripts/run-source.sh
```

Secunda has one player-facing engine path: it automatically selects the first compatible runtime it finds. There is no runtime picker in the product UI.

On Apple silicon, Secunda preferentially connects to a separately installed CrossOver app because it supplies the complete production graphics stack used for the Steam and game windows. It looks in this order:

1. `SECUNDA_CROSSOVER_APP` (an explicit CrossOver.app path)
2. `/Applications/CrossOver.app`
3. `~/Applications/CrossOver.app`
4. `build/vendor/CrossOver.app` while running this repository in development
5. The bundled or source-built Wine runtime as a fallback

Secunda never bundles, copies, or redistributes CrossOver. It uses that app's own bottle tool to create a dedicated `SkyrimSE-CrossOver` bottle beneath Secunda's application-support folder. The complete commercial runtime is intentionally separate from the supplied source-compliance archive; the archive remains useful for the fallback worker and its licenses, but does not represent the whole shipping product runtime.

The third-party source drop in `sources/` is intentionally excluded from Git. It remains local build input and carries its own component licenses.

## Package for local testing

Build the free runtime from the included source drop once:

```sh
brew install llvm lld bison
./scripts/build-runtime.sh
```

The build compiles the Wine worker from the supplied source archive, then downloads DXMT v0.80 from its official GitHub release, verifies SHA-256 `8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d`, and stages both into `Runtime/wine`.

Verify the actual Windows and DirectX 11 path on the current Mac:

```sh
./scripts/smoke-test-runtime.sh
```

Then package a local app. The default package is deliberately thin: it connects to
a separately installed CrossOver app and does not copy it into Secunda.

```sh
./scripts/package-app.sh
```

Set `SECUNDA_BUNDLE_RUNTIME=1` only for local technical experiments with the
source-built fallback. That fallback is intentionally excluded from the share path:
the proven player path is a separately installed CrossOver app.

## Create a shareable DMG

The share DMG contains the launcher, an Applications shortcut, and a short setup
guide. It excludes CrossOver, Steam, Skyrim, bottles, saves, logs, installers, and
account data.

```sh
./scripts/package-share-dmg.sh
```

It produces these two files in `dist/`:

- `Secunda Launcher-<version>.dmg`
- `Secunda Launcher-<version>.dmg.sha256`

The recipient installs their own CrossOver app from the [official download
page](https://www.codeweavers.com/crossover/download-now), then signs in to their
own Steam account inside Steam. This is important: the CrossOver EULA is for one
person at a time and restricts redistributing the app, while its official trial is
fully functional for 14 days. [CrossOver EULA](https://www.codeweavers.com/crossover/eula)

For a polished, warning-free handoff, sign and notarize with the publisher's Apple
Developer credentials:

```sh
SECUNDA_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
SECUNDA_NOTARY_PROFILE='secunda-notary' \
./scripts/package-share-dmg.sh
```

Without those credentials the script still makes an ad-hoc-signed testing DMG, but
macOS may show an extra first-open warning. Never ask a recipient to disable system
security for the app.

## Verify launcher contracts

```sh
./scripts/verify.sh
```

## Safety boundary

Runtime state, the Steam installer, the Skyrim bottle, saves metadata, backups, and logs live beneath:

```text
~/Library/Application Support/Secunda Launcher
```

Steam performs authentication itself. Secunda does not receive Steam credentials and does not bundle Steam or Skyrim.
