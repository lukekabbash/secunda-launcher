# Current architecture audit

## Executive diagnosis

Secunda is currently a capable but tightly coupled single-target executable. Game definitions, compatibility policy, process observation, settings persistence, launch orchestration, and UI projection cross too many boundaries. The architecture can remain one binary and one bottle while becoming substantially more isolated by making games declarative and moving all shared mutation behind one bottle-owned authority.

The clearest performance opportunities are not speculative renderer rewrites. They are removing repeated helper processes, overlapping host scans, synchronous I/O from main-actor presentation paths, broad UI invalidation, repeated compatibility writes, and redundant runtime/Steam discovery.

## Repository shape at inspection time

- Swift application lines: approximately 12,872.
- SwiftPM products: one executable.
- SwiftPM targets: one executable target at `app/`.
- Five `*SelfCheck.swift` files: approximately 2,636 lines compiled into the player executable.
- Bundled `Runtime/wine`: approximately 564 MB and 3,753 regular files.

Largest Swift files:

| File | Lines | Current responsibility concentration |
|---|---:|---|
| `Infrastructure/SelfCheck.swift` | 1,610 | Broad catalog, service, persistence, runtime, and packaging contracts in the shipped executable |
| `ViewModel/LauncherViewModel.swift` | 1,121 | Composition, navigation, settings, refresh, operations, process observation, presentation, AppKit access |
| `View/GameDetailView.swift` | 853 | Selection, actions, status, display, graphics, add-ons, saves, activity, I/O-triggering computed state |
| `Model/GameDescriptor.swift` | 731 | Game identity, presentation, installation, processes, compatibility, groups, lookup registry |
| `Service/GameProfileWriter.swift` | 719 | Path resolution, four file formats, mutation semantics, atomic I/O, readiness |
| `Service/GameService.swift` | 646 | Preconditions, capabilities, registry, profiles, Steam, direct launch, health, windows, diagnostics |

These six files contain about 44 percent of all application Swift. The problem is not only file length; each has multiple reasons to change.

## Confirmed high-priority hazards

### P0: runtime provenance does not describe the current source recipe

`scripts/build-runtime.sh` currently applies ten patches, including:

```text
patches/wine-secunda-compat-knobs.patch
```

`packaging/runtime-provenance.json` lists nine applied patches and omits that patch.

The current repository hash for:

```text
patches/wine-secunda-rosetta-debug-registers.patch
```

is:

```text
7d87673d14d2b2d6af194ffecf3b79fe8346b4842c1d27554cefc1b02e059e11
```

The provenance JSON records:

```text
43c3277132a7ef914d7ca9d8b70318593f5dde81741a2a4884ea4148d01569b4
```

Conclusion: the repository provenance cannot currently attest the inspected source/build recipe. This audit did not run the verifier and does not claim which recipe an existing packaged runtime contains.

### P0: incomplete desired-state cleanup can leak native audio across games

`VoiceAudioService.nativeDLLBaseNames` includes:

```text
x3daudio1_7
xactengine3_7
xaudio2_7
```

`BottleManager.gameDLLOverrides` omits `xactengine3_7`. A native-audio launch can set it to `native,builtin`; a later non-native launch builds its reset dictionary from the incomplete list and can leave that value behind.

Required architectural correction: Secunda-owned compatibility keys have complete desired state. Every key is set, deleted, or restored explicitly. No managed key is left unspecified.

### P0: backup ownership is ambiguous

`SaveService.backupPrefix` returns an empty string for Skyrim. `backupCount` uses `hasPrefix(backupPrefix)`, and every string begins with an empty prefix. Skyrim can therefore count all backup directories.

Required architectural correction: backup namespaces use a validated `StateDomainID`, and each snapshot carries a manifest. Legacy unprefixed backups require an explicit migration/classification path rather than empty-prefix matching.

### P0: UI task cancellation is not operation cancellation

`LauncherViewModel.stopActiveGameSpace()` cancels and clears its UI-owned task before calling Stop. `ProcessRunner.run` and `capture` use continuations without a structured cancellation handler. Cancelling the caller does not prove that an already launched helper or an awaited launch phase stopped.

Risk: a late helper completion or Steam handoff can continue after presentation state says the launch was cancelled and shutdown has begun.

Required architectural correction: a bottle generation is invalidated immediately on Stop; every awaited phase revalidates it; helper processes terminate and drain on cancellation; committed Steam/game processes require explicit managed-handle Stop.

### P1: process observation can overlap and stale-publish

The five-second observation loop calls `refreshBottleProcesses()`. That method starts another untracked `Task` and immediately returns. A slow `/bin/ps`/provenance scan can overlap later samples. There is no sample generation guarding publication.

Required architectural correction: one bottle monitor actor, single-flight sampling, bounded freshness, sequence/generation validation, and equality-guarded publication.

### P1: launch health can overstate success

Present source work has process and window-probe concepts, but visible-window health is not a universal graphical contract. Process persistence can still be mistaken for a usable launch on paths that do not require a visible surface.

Required architectural correction: record separate launch milestones and give graphical definitions an explicit health contract. Product status must distinguish request, handoff, stable process, presentable surface, and live acceptance.

### P1: Steam compatibility can inherit title state

`openSteam()` applies a default compatibility profile before requesting Steam. That can only neutralize keys represented by the default profile. Incomplete desired state, session-wide DPI/Retina/sync state, or environment retained by a warm Steam process can continue across titles.

Required architectural correction: a complete title-neutral Steam profile, an applied session fingerprint, and quiet-bottle transition rules.

## Confirmed performance hot paths

### Repeated Wine process queries

`WindowsProcessProbe.snapshot` loops over every candidate image and runs a separate Wine `tasklist` query for each. Health polling repeats at approximately 500–750 ms intervals across a ten-second stability window.

For one or two image names, this can create roughly 14–28 Wine helper launches in one health window. The ten-second stability gate is useful; the observation mechanism is unnecessarily expensive.

### Full host process reconciliation every five seconds

`BottleProcessInspector.runningProcesses`:

- launches `/bin/ps -axo`;
- parses the complete host process table;
- calls `proc_pidpath` for candidates;
- can perform filesystem provenance checks;
- includes processes from other Secunda runtimes for recovery visibility.

This broad scan is useful for recovery but too expensive and too broad to be the ordinary game-presence hot path.

### Multiple registry helpers per compatibility application

`BottleManager.applyGameCompatibility` launches one `wine reg add` helper per DLL override and additional helpers for graphics/display/Mac-driver state. A typical launch can therefore start approximately eight to ten registry helpers even if desired state is already applied.

### Main-actor filesystem and service work

`LauncherViewModel.refresh()` performs synchronous installation, save, backup, artwork, and profile checks while main-actor isolated. View-facing computed paths also perform file existence checks. `SettingsView` can enumerate logs and read a large excerpt as presentation state is evaluated.

### Settings authority and write amplification

Settings currently live in one unversioned document. Decode failure can fall back to defaults without a durable migration/quarantine authority, and individual UI edits replace the complete settings value and synchronously rewrite the document. Requested fast-sync policy and actually applied session state are not cleanly separated.

Required architectural correction: versioned global plus state-domain settings, stable choice IDs, an actor that coalesces and orders writes, explicit corrupt-document recovery, and applied session truth in the session ledger.

### Duplicated catalog/group authority

The supported-game registry and game-group construction are both maintained centrally, while mode titles and several profile/diagnostic decisions are recovered through game-ID switches elsewhere. This makes adding or changing one game a cross-repository edit rather than a local definition change.

Required architectural correction: one validated catalog construction path, one definition/family file per game, and a structural check that concrete game IDs do not escape GameSupport, migrations, or tests.

### Broad UI invalidation

Every major screen observes the same `ObservableObject`. Any process sample, settings copy, activity item, navigation change, error, or unrelated game change invalidates all mounted observers. The detail view then recomputes work that includes synchronous I/O.

### Runtime integrity and discovery

The bundled runtime is about 564 MB with thousands of manifest entries. Full verification is necessary at the correct boundary but should not be repeated for routine SwiftUI refresh. Runtime version probing should capture a small bounded result directly, not append and reread an accumulated log.

## Current performance evidence

Checked-in status documentation records one title/scene with:

- about 28.2 FPS at 1920x1080;
- about 32.2 FPS at 1440x900;
- 31.02 ms average present interval;
- 36.16 ms P95 present interval;
- roughly 15 ms GPU work while Low Power Mode was enabled;
- about 805 MiB RSS with a 0.6 MiB short-run range;
- sync-interval disabling slightly worse than the retained setting;
- the translated child not visibly receiving Game Mode.

These figures must not be generalized across games. They establish that global VSync disabling is not supported by current evidence and that launcher monitoring interference should be measured against frame-time tails rather than assumed to improve average FPS.

## Observations, inferences, and unvalidated experiments

Confirmed observations:

- The process-query, host-scan, registry-helper, UI-invalidation, and main-actor-I/O patterns exist in source.
- The current provenance and patch recipe disagree.
- Low Power Mode and Game Mode state were recorded in existing project evidence.

Strong inferences requiring measurement:

- Removing overlapping process scans should reduce launcher CPU, wakeups, and I/O.
- It may improve P95/P99 game frame time if current scans interfere with scheduling.
- Compatibility fingerprinting should substantially reduce launcher-owned handoff work.

Unvalidated experiments:

- A native/helper path for actual Game Mode eligibility.
- Narrower or title-aware AVRT priority behavior.
- Any renderer or shader-cache topology change.
- A long-lived Windows-side process watcher.

No experiment becomes product policy without isolated A/B evidence and cross-game acceptance.
