# Secunda Launcher

Secunda is a focused, unofficial Apple-silicon launcher for a separately owned Steam copy of Skyrim Special Edition. It is intentionally narrow: one source-built compatibility runtime, one isolated Windows prefix, Steam, and Skyrim.

Secunda does not discover or depend on CrossOver.app. Its player path is:

```text
Secunda.app -> source-built Wine 11.0 + DXMT 0.80 -> private prefix -> Windows Steam -> Skyrim -> Metal/CoreAudio
```

Steam performs authentication and ownership checks itself. Secunda never asks for a Steam password and does not bundle Steam, Skyrim, account sessions, game files, or saves.

## Platform

- Apple-silicon Mac
- macOS 15 or newer
- Rosetta 2 for the x86-64 Windows worker

The Secunda interface is native arm64. Wine, Windows Steam, and Skyrim are x86-64 and run through Rosetta; Direct3D 11 is translated to Metal by the open-source DXMT bridge.

## Current source run

The supplied compliance archive must already be extracted beneath `sources/`, and a source runtime must exist at `Runtime/wine`.

```sh
./scripts/run-source.sh
```

There is no player-facing runtime picker. A packaged build uses only its bundled, manifest-bearing source runtime. A development run may use the repository runtime or an explicit `SECUNDA_WINE_BIN`, but source-only policy rejects proprietary paths and payload identities.

## Build the runtime

Building requires Xcode Command Line Tools plus Homebrew LLVM, LLD, Bison, CMake, and Ninja. These are build-time tools; a DMG recipient does not need them.

```sh
brew install llvm lld bison cmake ninja
./scripts/build-runtime.sh
./scripts/smoke-test-runtime.sh
```

The build verifies pinned inputs, applies the patches listed in `packaging/runtime-provenance.json`, targets macOS 15, relocates dynamic-library paths, stages notices and licenses, creates an integrity manifest, and rejects proprietary or user payloads.

## Verify the launcher and runtime

```sh
./scripts/verify.sh
./scripts/test-gate-observability.sh
./scripts/verify-runtime-distribution.sh Runtime/wine
```

Live acceptance status and evidence are maintained in `docs/source-only/GATES.md`. A command succeeding is not treated as gameplay proof: acceptance requires visible Steam, rendered gameplay, audio, keyboard/mouse input, save, clean quit, relaunch, and load.

## Build a shareable DMG

Provide the exact supplied source archive when packaging so the DMG can carry corresponding source alongside the binary runtime:

```sh
SECUNDA_SOURCE_ARCHIVE=/path/to/crossover-sources-26.3.0.tar.gz \
./scripts/package-share-dmg.sh
```

The output is:

- `dist/Secunda Launcher-<version>.dmg`
- `dist/Secunda Launcher-<version>.dmg.sha256`

The DMG contains Secunda, the source-built runtime, an Applications shortcut, recipient instructions, notices, an SPDX SBOM, checksums, build scripts, patches, and corresponding source. It contains no Steam client, Skyrim files, prefix, credentials, sessions, saves, or logs.

For a warning-free public handoff, sign and notarize with the publisher's Apple Developer credentials:

```sh
SECUNDA_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
SECUNDA_NOTARY_PROFILE='secunda-notary' \
SECUNDA_SOURCE_ARCHIVE=/path/to/crossover-sources-26.3.0.tar.gz \
./scripts/package-share-dmg.sh
```

Without those credentials the release command fails closed. For local packaging tests only, explicitly set `SECUNDA_TEST_ONLY_UNNOTARIZED_DMG=1`; the output is labeled `TEST-ONLY`, is not recipient-ready, and may show an additional first-open warning. Recipients should never be asked to disable macOS security.

## Managed data and removal

All mutable player data stays beneath:

```text
~/Library/Application Support/Secunda Launcher
```

That directory contains the managed Windows prefix, Steam installation/session, Skyrim installation, saves, backups, caches, and logs. Removing Secunda.app does not silently delete it; archive wanted saves before removing the managed data directory.

## Licensing status

Runtime component licenses, notices, corresponding source, and checksums are staged by the packaging pipeline. Secunda's own launcher-code license still needs to be selected by the project owner before publishing the repository as a broadly reusable open-source project.
