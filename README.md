# Secunda Launcher

Secunda is an unofficial Apple-silicon launcher for Windows Steam games you already own. It is early software: a listed title is not a guarantee it works. Steam still handles sign-in and ownership. Secunda never asks for a Steam password and never bundles a game, account session, save, or Steam client.

It is intentionally bounded: one compatibility runtime, one private game space (a managed Windows environment for Steam and your games), and explicit per-game profiles — not a generic “run any Windows app” button.

## What this work in progress is for

The practical goal is to keep a game’s runtime, game space, Steam handoff, launch settings, display profile, and clean stop behavior in one place. Secunda is still early. It is useful for trying these paths, not a promise that every catalog entry will work or that a launch attempt is gameplay proof.

## Start here

Clone the source branch, then run from source or package a local Finder app. The packaged `.app`, DMGs, and rebuilt Wine runtime stay in `dist/` and `Runtime/` on your machine; they are not committed.

```sh
git clone --branch source-only-secunda https://github.com/lukekabbash/secunda-launcher.git
cd secunda-launcher
```

A Finder-launchable app is produced after the source runtime exists at `Runtime/wine`:

```sh
./scripts/package-app.sh
open "dist/Secunda Launcher.app"
```

This is an **ad-hoc-signed, TEST-ONLY work-in-progress build**, not a notarized public release. macOS may show a first-open warning. Please do not weaken macOS security settings to run it; wait for a Developer ID–signed, notarized release if the normal macOS checks do not allow it to open.

The app creates its own private Windows prefix, then Steam handles normal sign-in, ownership, and game installation. It does not make a game compatible merely by listing it. The current state of each title is described below and in `docs/source-only/GATES.md`.

## Compatibility, honestly

This catalog is a work in progress. Proven here means played on a 2026 MacBook Air M5 with 24 GB of memory. A listing is still not a guarantee on every Mac.

| Title or group | Current status |
| --- | --- |
| Skyrim Special Edition | Proven working on a 2026 MacBook Air M5 (24 GB). |
| Fallout 4 | Proven working on a 2026 MacBook Air M5 (24 GB). |
| Supreme Commander 2 | Proven working on a 2026 MacBook Air M5 (24 GB). |
| Insurgency | Proven working on a 2026 MacBook Air M5 (24 GB). |
| Black Ops II | Has unresolved compatibility issues; campaign is not currently playable in this source-runtime path, and the other modes still need full visual, audio, input, and gameplay acceptance. |
| Battlefront II Classic, Supreme Commander, Supreme Commander: Forged Alliance, and Angels Fall First | Catalog profiles. Untested or unproven. Do not treat them as supported. |

A compact compatibility label for every catalog entry is the next repository-facing documentation step. Gate evidence remains in `docs/source-only/GATES.md`. “Listed” never means “guaranteed.”

### Why generated artifacts stay out of Git

The packaged app and Wine runtime are hundreds of megabytes and rebuild often. They remain local under `dist/` and `Runtime/`. Generated DMGs, build caches, source archives, managed bottles, Steam data, games, saves, logs, and credentials also stay out of the repository. A future signed and notarized DMG belongs in GitHub Releases, not in commit history.

Secunda does not discover or depend on CrossOver.app. Its player path is:

```text
Secunda.app -> source-built Wine 11.0 + packaged graphics translation -> private prefix -> Windows Steam -> selected game -> macOS graphics/audio
```

## Supported library

The current catalog contains:

- The Elder Scrolls V: Skyrim Special Edition
- Fallout 4
- Supreme Commander and Supreme Commander: Forged Alliance
- Supreme Commander 2
- STAR WARS Battlefront II (Classic, 2005)
- Insurgency
- Angels Fall First
- Call of Duty: Black Ops II — Campaign, Multiplayer, and Zombies

Skyrim Special Edition, Fallout 4, Supreme Commander 2, and Insurgency are proven on a 2026 MacBook Air M5 with 24 GB of memory. Supreme Commander, Forged Alliance, Battlefront II Classic, and Angels Fall First remain catalog profiles, not gameplay-acceptance claims. A listing means Secunda knows a title’s Steam identity, installation layout, and launch profile.

## Platform

- Apple-silicon Mac
- macOS 15 or newer
- Rosetta 2 for the x86-64 Windows worker

The Secunda interface is native arm64. Its Intel runtime workers run through Rosetta and support both 32-bit and 64-bit Windows game processes. Each catalog profile selects the packaged graphics path appropriate to that game.

## Build and run from source

If you want to run the launcher without packaging a Finder app, the supplied compliance archive must already be extracted beneath `sources/`, and a source runtime must exist at `Runtime/wine`.

```sh
./scripts/run-source.sh
```

There is no player-facing runtime picker. A packaged build uses only its bundled, manifest-bearing source runtime. A development run may use the repository runtime or an explicit `SECUNDA_WINE_BIN`, but source-only policy rejects proprietary paths and payload identities.

After building the runtime, make a Finder-launchable local app with:

```sh
./scripts/package-app.sh
open "dist/Secunda Launcher.app"
```

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

Live acceptance status and evidence are maintained in `docs/source-only/GATES.md`. A catalog entry or successful command is not gameplay proof: acceptance requires visible Steam, rendered gameplay, audio, keyboard/mouse input, save where supported, clean quit, relaunch, and load.

## Build a shareable DMG

Provide the exact supplied source archive when packaging so the DMG can carry corresponding source alongside the binary runtime:

```sh
SECUNDA_SOURCE_ARCHIVE=/path/to/crossover-sources-26.3.0.tar.gz \
./scripts/package-share-dmg.sh
```

The output is:

- `dist/Secunda Launcher-<version>.dmg`
- `dist/Secunda Launcher-<version>.dmg.sha256`

The DMG contains Secunda, the source-built runtime, an Applications shortcut, recipient instructions, notices, an SPDX SBOM, checksums, build scripts, patches, and corresponding source. It contains no Steam client, supported-game files, prefix, credentials, sessions, saves, or logs.

For a warning-free public handoff, sign and notarize with the publisher's Apple Developer credentials:

```sh
SECUNDA_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
SECUNDA_NOTARY_PROFILE='secunda-notary' \
SECUNDA_SOURCE_ARCHIVE=/path/to/crossover-sources-26.3.0.tar.gz \
./scripts/package-share-dmg.sh
```

Without those credentials the release command fails closed. For local packaging tests only, explicitly set `SECUNDA_TEST_ONLY_UNNOTARIZED_DMG=1`; the output is labeled `TEST-ONLY`, is not recipient-ready, and may show an additional first-open warning. Recipients should never be asked to disable macOS security. When the app is ready for broader sharing, publish that notarized DMG as a GitHub Release asset rather than committing it.

## Managed data and removal

All mutable player data stays beneath:

```text
~/Library/Application Support/Secunda Launcher
```

That directory contains the managed Windows prefix, Steam installation/session, installed games, saves, backups, caches, and logs. Removing Secunda.app does not silently delete it; archive wanted saves before removing the managed data directory.

## Licensing status

Runtime component licenses, notices, corresponding source, and checksums are staged by the packaging pipeline. Secunda's own launcher-code license still needs to be selected by the project owner before publishing the repository as a broadly reusable open-source project.
