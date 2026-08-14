# Performance plan

## Performance taxonomy

Keep three performance problems separate:

1. Launcher responsiveness: app startup, refresh, navigation, artwork, settings, and process UI.
2. Launch orchestration: runtime lookup, process snapshots, compatibility, profiles, Steam request, handoff, and health checks.
3. Game performance: average/P95/P99 frame time, stutter, input latency, audio stability, memory, and fidelity.

Architecture work can strongly improve the first two. It can reduce interference with the third, but it does not inherently increase FPS.

## Priority order

1. Make bottle/host process scans single-flight.
2. Collapse per-image Wine `tasklist` calls into one indexed snapshot.
3. Remove nested unstructured process-refresh tasks and stale publication.
4. Short-circuit/cadence-limit host reconciliation and cache provenance.
5. Compile, fingerprint, diff, and batch compatibility state.
6. Share one fresh inventory within a launch transaction.
7. Replace process continuations/timeouts with structured supervision.
8. Add runtime, Steam, capability, and profile caches with explicit invalidation.
9. Remove filesystem/log/image decoding from main-actor presentation paths.
10. Run frame-impact A/B captures before renderer or scheduling policy changes.

## Windows process sampling

### Immediate design

Execute once per sample:

```text
tasklist /FO CSV /NH
```

Requirements:

- bounded output;
- bounded timeout;
- parse all rows once;
- index by normalized image name;
- answer every game/launcher alias from the index;
- share the snapshot among all consumers in the transaction;
- report malformed/overflow samples as an explicit unknown state rather than false absence.

Target:

- at most one Wine helper per sampling cycle;
- no per-image helper loop;
- one sample in flight;
- callers can request forced-fresh or accept a declared freshness window.

### Optional later watcher

Only if measurements show the one-helper sample remains material:

- add one narrowly scoped Windows-side process transition watcher;
- emit allowlisted image/PID transitions;
- retain slow host reconciliation for missed/manual/orphan processes;
- keep watcher failure nonfatal and observable.

Do not start with a custom watcher before the simple indexed query is benchmarked.

## Host process monitoring

### Single-flight monitor

Concurrent callers join one task:

```swift
func snapshot(_ freshness: SnapshotFreshness) async throws -> ProcessSnapshot
```

The monitor records:

- scan sequence;
- start/end time;
- reason;
- joined-caller count;
- helper count;
- candidate count;
- `proc_pidpath` count;
- provenance lookup count;
- result freshness.

### Cost ladder

1. Known managed process exit events.
2. Known PID/start-identity validation.
3. Command-text and bottle/runtime path filters.
4. `proc_pidpath` only for unresolved likely Wine candidates.
5. Cached executable provenance keyed by path plus filesystem identity.
6. Full all-Secunda recovery scan only on its slower cadence or explicit demand.

### Cadence

Provisional policy:

- during launch/stop: forced fresh at defined state boundaries;
- during active play: event-driven plus full reconciliation every 15–30 seconds;
- while Steam-only: slower bounded cadence;
- while cold/idle: suspend routine full scans;
- Settings recovery list: explicit refresh with a visible timestamp.

Never create another task from inside a timer callback and return before it finishes.

## Compatibility application

### Compiler

`CompatibilityProfileCompiler` converts a game/session plan into a canonical complete desired-state document.

Inputs:

- bottle ID/generation;
- runtime capabilities;
- profile schema;
- exact executable aliases;
- desired DLL/renderer/Mac/display values;
- session policy.

Outputs:

- canonical mutation list;
- deterministic digest;
- verification query plan;
- optional bounded `.reg` transaction.

### Fast paths

- Matching applied fingerprint: zero helpers and zero registry writes.
- Changed compatible state: generally one registry import and one bounded verification.
- Missing monotonic capability: install/verify capability, then reconcile.
- Non-quiet session-wide change: queue/reject until the bottle is quiet; never mutate under an active game.

Never edit Wine registry files directly while wineserver is active.

## Shared launch inventory

At launch admission, take one forced-fresh snapshot containing:

- current managed process identities;
- wineserver/session fingerprint;
- Steam state;
- runtime descriptor;
- bottle generation;
- installation snapshot.

Use it for initial safety decisions. Perform one final targeted fresh check before the irreversible launch request. Do not independently rerun identical full scans for each precondition.

## Runtime catalog cache

Cache the live descriptor by:

- canonical runtime path;
- runtime build ID;
- app bundle identity;
- provenance/manifest digest;
- relevant filesystem identity.

Rules:

- capture `wine --version` directly with a small limit and timeout;
- never append to and reread an accumulated version log;
- do not repeat full integrity hashing during ordinary UI refresh;
- invalidate in memory when the bundle/runtime/provenance identity changes.

A persistent integrity-attestation receipt is trustworthy only when bound to an immutable signed/notarized artifact and exact manifest/code-signature identity. While builds are ad-hoc signed, cold full verification remains authoritative.

## Steam library index

Build one `SteamLibraryIndex`:

- parse `libraryfolders.vdf` once per source identity;
- index app manifests by `SteamAppID`;
- watch `steamapps` directories, not individual files that Steam may atomically replace;
- debounce directory events;
- re-arm after rename/delete;
- retain a periodic metadata fallback;
- invalidate only affected app IDs;
- publish equality-guarded game installation changes.

## Capability and file receipts

DXVK/native-audio validation receipts are keyed by:

- bottle ID/generation;
- capability version;
- file identity;
- size;
- modification time;
- expected digest.

Revalidate when metadata changes and always after replacement/repair.

Profile writes:

- compute new content off-main;
- skip atomic write when bytes are unchanged;
- return a receipt containing target identity, before/after digest, and mutation count;
- never reread unchanged files merely to update UI state.

## UI and artwork performance

- Move all scanning, log reads, manifest parsing, file checks, and image decode off the main actor.
- Diff scan results before assigning observable state.
- Observe the smallest store capable of changing the rendered pixels.
- Downsample artwork to target pixel size before creating display images.
- Cache by artwork identity, source fingerprint, target size, and crop policy.
- Use a cost-limited cache rather than an unbounded dictionary.
- Cache blurred/letterbox backgrounds instead of rendering a second full image with a large blur on every card.
- Failure entries have TTL or file-change invalidation.
- SwiftUI task cancellation cancels underlying artwork work.

## Runtime footprint

Current candidate-only development material in `Runtime/wine`:

| Category | Approximate size |
|---|---:|
| Headers | 62.4 MB |
| Static/import/development libraries | 22.7 MB |
| Developer-oriented command-line tools | 1.8 MB |
| Total candidate SDK/player split | 86.9 MB |

Do not delete these directly from the working runtime.

Create:

- `RuntimeSDK`: complete build/development artifact.
- `PlayerRuntime`: allowlisted, content-addressed, package-verified runtime.

The player allowlist must retain all required:

- Wine/wineserver/wineboot;
- registry and process-query tools;
- 32-bit and 64-bit workers/loaders;
- DXMT/DXVK/MoltenVK components;
- audio/controller payloads;
- managed helpers;
- notices, SBOM, source/provenance records.

Player-runtime reduction affects distribution and integrity-scan cost, not FPS. Preserve 32-bit support.

## Shipped self-check footprint

Move fixture-heavy self-checks into test targets. Keep a small packaged health check for:

- catalog construction;
- runtime/provenance readability;
- required player payload/capabilities;
- critical contamination invariants;
- bounded path containment checks.

Do not make a package launch execute thousands of broad source-level fixture contracts.

## Game-frame investigation

### Current evidence constraints

- Do not disable VSync globally; checked-in evidence found it slightly worse.
- Low Power Mode was active during the recorded GPU capture; report it, never mutate the user's global setting.
- The measured scene was not proven purely GPU-bound.
- Game Mode was not visibly active for the translated child.

### Credible near-term experiments

1. Current monitoring versus optimized monitoring with identical gameplay capture.
2. Power mode controlled by the user, with identical thermal and display conditions.
3. Game Mode eligibility experiment, accepted only when the child is visibly reported active.
4. Existing AVRT policy versus narrower/task-aware or title-opt-in policy.
5. Per-title renderer/quality/resolution experiments.
6. Cold and warm shader-cache traversal measured separately.

### Cache policy

- Do not clear caches as routine launch behavior.
- Do not split DXMT caches without collision or diagnostic evidence.
- Namespace DXVK state/cache paths where executable collisions or repair survival require it and the injection path is valid.
- Keep diagnostic shader instrumentation separate from clean frame-time runs.

## Instrumentation contracts

Use `ContinuousClock` and low-overhead signposts.

Launch phase durations:

- runtime locate;
- runtime integrity decision;
- process snapshot;
- plan compile;
- capability ensure;
- compatibility reconcile;
- profile apply;
- Steam/direct request;
- target first seen;
- target stable;
- presentable window;
- terminal outcome.

Counters:

- helper launches by role;
- process scan requests, joins, overlaps, and freshness;
- `proc_pidpath` and provenance calls;
- filesystem probes;
- registry writes/imports;
- profile bytes read/written/skipped;
- captured/logged bytes;
- timeouts and cancellations;
- actor queue wait;
- main-actor duration;
- UI state assignments/invalidation scope.

Stamp events with bottle/session/operation/launch identity. Exclude credentials, raw environment dumps, private arguments, and unbounded paths/logs.

## Benchmark suite

### `LaunchOrchestrationTrace`

- cold and warm runs;
- at least five runs per configuration;
- per-phase duration;
- helper/registry/scan counts;
- p50, p95, p99, max.

### `ProcessMonitorIdleProbe`

- ten minutes launcher idle;
- ten minutes during gameplay;
- CPU, wakeups, disk writes, scans, overlaps, provenance calls;
- current versus candidate monitor.

### `RunnerLifecycleStress`

- immediate exit;
- launch failure;
- timeout;
- cancellation before/after spawn;
- output overflow;
- inherited pipe behavior;
- exact-once completion;
- simulated PID reuse;
- zero retained records.

### `RegistryProfileBench`

- cold application;
- changed application;
- no-op application;
- verify global and executable-scoped state;
- verify complete cleanup of prior game values.

### `RuntimeIndexBench`

- cold full verification;
- memory-cached lookup;
- changed manifest;
- changed runtime file;
- failed receipt;
- signed persistent receipt when available.

### `FrameImpactA/B`

Hold constant:

- save/scene;
- camera/route;
- resolution/display;
- fidelity and frame-pacing settings;
- power mode;
- thermal state;
- capture duration;
- diagnostics mode.

Report average, p95, p99, max, one-percent lows where valid, and over-budget frame count.

### `ShaderCacheA/B`

- cold first traversal;
- warm repeated traversal;
- separate instrumented shader run;
- separate clean performance run.

## Provisional budgets

These are proposed contracts to calibrate, not current measurements.

| Path | Target |
|---|---|
| Initial useful UI | <=300 ms p50; <=600 ms p95 |
| Main-actor slice | <=4 ms p95; no filesystem/process work |
| Warm runtime lookup | <=50 ms p95 |
| Launcher-owned pre-handoff | <=300 ms p95 excluding vendor startup/health wait |
| No-op compatibility | 0 Wine helpers; 0 registry writes |
| Changed compatibility | <=1 registry import |
| Windows process sample | <=1 Wine helper |
| Monitor concurrency | exactly 1 scan in flight per bottle |
| Gameplay launcher CPU | <0.5% average on target Mac |
| Diagnostics-off monitor/log writes | 0 verbose bytes/minute |
| Routine launcher wakeups during play | <4/second excluding supervised game/Steam activity |
| Frame interference | p95/p99 delta <0.25 ms and <1% more over-budget frames |
| Cancellation acknowledgement | <=100 ms |
| Probe cancellation/drain | <=250 ms normally; bounded force stop <=2 s |
| Terminal process records | 0 retained |

## Migration regression guardrails

- Initial-ready median: no more than 5 percent slower.
- Initial-ready/refresh P95: no more than 10 percent slower.
- Click-to-Steam request: no more than 5 percent or 250 ms slower.
- Idle CPU: no more than 0.5 percentage point or 10 percent worse.
- RSS: no more than 5 percent or 25 MiB worse.
- Game average and P95 frame time: no more than 2 percent worse.

## Meaningful optimization thresholds

Accept a claimed optimization when it produces approximately:

- at least 10 percent P95 latency improvement;
- at least 20 percent reduction in polling subprocesses, wakeups, or CPU;
- at least 10 percent or 25 MiB memory reduction;
- at least 5 percent game frame-time improvement with p95, fidelity, and stability no worse;
- or a structural contract such as zero overlap, zero no-op writes, or exact cancellation that removes a correctness risk.

## Performance anti-patterns

- Do not claim target splitting raises FPS.
- Do not trade package integrity for faster verification.
- Do not cache mutable/ad-hoc runtime integrity across launches without a trustworthy artifact identity.
- Do not add a long-lived watcher before measuring the simple indexed query.
- Do not log verbose renderer output during ordinary play.
- Do not clear shader caches to make a benchmark look consistent without separately reporting cold/warm behavior.
- Do not combine multiple experiments into one candidate build and infer causality.

