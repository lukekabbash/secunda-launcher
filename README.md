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

## Package a local app

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

Then package the launcher and fallback runtime:

```sh
./scripts/package-app.sh
```

The resulting `dist/Secunda Launcher.app` is ad-hoc signed for local testing. It detects a separately installed CrossOver app at launch and never embeds it in the package. Public sharing still requires Developer ID signing and notarization. Wine source and license obligations remain applicable; DXMT v0.80 is included under its MIT license.

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
