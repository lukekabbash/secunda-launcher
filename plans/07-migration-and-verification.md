# Migration and verification plan

## Migration doctrine

- No flag-day rewrite.
- Separate behavior corrections from mechanical file/target movement.
- Establish behavior fingerprints before replacing authority.
- Introduce new code behind forwarding adapters.
- Migrate one game or one responsibility at a time.
- Keep one obvious rollback boundary per change.
- Add Swift target boundaries after APIs stabilize.
- Run performance work as isolated experiments.
- Remove legacy shims last.

## Phase 0: preserve current work and restore truth

### Deliverables

- Classify the current dirty work into coherent areas:
  - game/profile behavior;
  - session/process/runtime behavior;
  - patches/build/provenance;
  - UI/presentation;
  - packaging/docs/evidence.
- Preserve user-owned changes without overwriting or combining unrelated work.
- Reconcile build patch list and provenance hashes.
- Correct incomplete DLL desired state.
- Replace empty-prefix backup ownership.
- Prevent a cancelled launch from continuing after Stop.
- Define and verify title-neutral Steam compatibility state.
- Record the current accepted/unaccepted state per game and per package.

### Gate

- No known shared-state leak remains unrepresented.
- Provenance truthfully describes the selected build recipe.
- Existing accepted title behavior has a timestamped baseline.

### Rollback

Retain the current launcher/runtime baseline as the hard fallback. Do not mix Phase 0 corrections with module relocation.

## Phase 1: characterization and baseline evidence

### Behavior fingerprints

For every definition record:

- game/group/state/process-domain IDs;
- Steam app IDs;
- installation executable and baseline files;
- game and launcher process aliases;
- launch strategy and arguments;
- renderer, voice, DPI, Retina, sync, decoration, and feature policies;
- configuration target/recipe/defaults;
- save, backup, cache, log, and diagnostic targets;
- launch health contract;
- display/session fingerprint inputs.

### Performance baseline

- app initial-useful timing;
- refresh timing and filesystem/process counts;
- click-to-Steam request phases;
- helper/registry/scan counts;
- ten-minute idle/play monitor CPU, wakeups, and writes;
- current frame-time capture where repeatable;
- app/runtime/package sizes and build/package timings.

### Gate

- Baseline artifacts are reproducible and identify exact source/runtime/package IDs.
- No production behavior has changed.

## Phase 2: domain types and validated catalog

### Deliverables

- `SecundaDomain` target.
- Validated IDs and paths.
- Composed `GameDefinition` and groups.
- Catalog validation errors.
- Legacy `GameDescriptor` adapter backed by the new catalog.
- Structural rule that concrete game IDs remain in GameSupport, migrations, and tests.

### Gate

- Legacy and new catalogs produce identical ordering, IDs, labels, groups, process identities, policies, and defaults.
- Malformed definitions fail deterministically.
- Current service/UI callers continue using the adapter.

### Rollback

Remove the adapter/target without touching current launch authority.

## Phase 3: per-game definition migration

Migrate the lowest-complexity profile first and the highest-risk translated/protected/multi-mode profiles last.

Suggested order for the current catalog:

1. Battlefront II Classic: simple vertical slice.
2. Insurgency: aliases, KeyValues, window policy.
3. Supreme Commander plus Forged Alliance: deliberate shared family/group/process behavior.
4. Supreme Commander 2.
5. Angels Fall First: direct launch, DXVK/window behavior.
6. Skyrim plus Fallout 4: broad configuration/audio/display behavior.
7. Black Ops II modes: shared state, 32-bit/protected-startup constraints, partial acceptance.

Each migration change contains:

- one definition/family;
- one catalog registration;
- fixtures;
- legacy fingerprint equality;
- no shared service or UI redesign.

### Gate per game

- No game-ID switch added outside allowed locations.
- Definition validates.
- Legacy fingerprint is equal.
- Pure tests pass.
- Existing live/package acceptance status is preserved, not automatically promoted.

## Phase 4: pure configuration editors

Order:

1. Writable sectioned INI.
2. Existing-key-only sectioned INI.
3. Quoted KeyValues.
4. Bounded Lua preferences.

### Deliverables

- Pure editors.
- Fixture corpus for CRLF/LF, comments, duplicates, missing sections/keys, malformed input, and idempotence.
- One contained atomic plan executor.
- Before/after receipts.
- No production shadow writes.

### Gate

- Expected files are byte-identical where no semantic change is requested.
- Reapplication is byte-stable.
- Existing-only recipes never create undeclared keys.
- Traversal/symlink targets fail closed.

## Phase 5: coordinator, monitor, and process supervisor

### Order of authority transfer

1. Coordinator wraps the current launch facade without changing behavior.
2. Move operation admission/exclusive lease.
3. Move generation and stop invalidation.
4. Move session fingerprint authority.
5. Move compatibility application.
6. Move capability installation.
7. Move process sampling and health.
8. Move exact Stop.
9. Separate broad recovery.
10. Replace `ProcessRunner` lifecycle with supervised handles.

Transfer one responsibility per focused change.

### Gate

- All mutations use the coordinator.
- No stale phase publishes after generation change.
- Cancellation and timeout deliver exactly once.
- Helper processes drain and disappear.
- Committed game/Steam processes are stopped only explicitly.
- Exact Stop cannot target another bottle/runtime through broad provenance.

## Phase 6: settings and game-state ownership

### Deliverables

- `StateDomainID` and manifests.
- Versioned global plus state-domain settings.
- Settings actor and coalesced writes.
- Applied session state moved from preferences into the ledger.
- Manifest-backed backup/reset/restore.
- v0 -> v1 -> v2 staged migration with hashes and receipt.

### Gate

- Migration is interruptible and resumable at every step.
- Invalid settings are preserved and surfaced.
- One game/state-domain failure cannot reset another.
- Cache clear, uninstall, restore, and rebuild have disjoint exact effects.
- Legacy input remains recoverable for an accepted release cycle.

## Phase 7: UI projections

### Order

1. Mechanical view extraction.
2. Typed navigation/alerts.
3. Assembly root.
4. Single-flight off-main scanner.
5. Stable library/sidebar game stores.
6. Group selection and per-game settings stores.
7. Scoped operation/session/activity stores.
8. Narrow Settings stores.
9. Artwork repository.
10. Remove legacy view-model facade.

### Gate

- No view-body I/O.
- Unchanged scans assign nothing.
- Game A progress/artwork/settings cannot affect Game B presentation.
- Stale scans cannot publish.
- Main-actor and UI invalidation budgets pass.

## Phase 8: package target enforcement

Move code after the APIs above are stable:

1. `SecundaDomain`.
2. `SecundaGameSupport`.
3. `SecundaRuntime`.
4. `SecundaApplication`.
5. `SecundaUI`.
6. Thin `SecundaLauncher` composition.
7. Focused test targets and small packaged health check.

### Gate

- Dependency graph is acyclic.
- Application does not import concrete runtime implementation.
- Runtime and Application contain no concrete game-ID switches.
- UI imports no low-level process/filesystem implementation.
- Packaging copies/verifies every required output.

## Phase 9: isolated performance work

One candidate per change:

- indexed Windows process sample;
- host-monitor single flight and cadence;
- provenance cache;
- compatibility fingerprint and batch import;
- runtime catalog cache;
- Steam library index;
- capability receipts;
- artwork downsampling/cache;
- player runtime projection;
- Game Mode experiment;
- AVRT policy experiment;
- per-title renderer/fidelity experiments.

### Gate

- Baseline and candidate identify exact source/runtime/configuration.
- Regression guardrails pass.
- Claimed metric crosses its meaningful-improvement threshold or removes a structural correctness risk.
- Cross-game acceptance passes for any shared behavior change.

## Phase 10: remove legacy shims

Remove:

- legacy descriptor/catalog switches;
- legacy profile switches;
- old service facade paths;
- old settings schema after retention policy;
- broad self-check fixtures from product target;
- legacy UI view model.

### Gate

- Every game is definition-backed.
- Two consecutive package acceptance cycles pass.
- All cross-game transition sequences pass.
- Canonical runtime/package provenance passes.
- Rollback artifacts and migration receipts exist.

## Verification layers

### Layer 1: pure unit tests

- IDs and safe paths;
- catalog validation;
- launch/display/compatibility planning;
- configuration editors;
- settings migrations;
- state manifests;
- state machine and generation rules;
- reducers and stable UI projections.

No live runtime.

### Layer 2: per-profile contracts

- complete fingerprint per game;
- exact executable aliases;
- supported options/defaults;
- desired registry state including deletes/restores;
- profile output fixtures;
- state/backup/log ownership;
- structural concrete-game-ID boundary check.

### Layer 3: temp filesystem and fake-port integration

- Steam library/manifests;
- path containment and symlinks;
- settings atomicity/interruption;
- backup/restore/reset receipts;
- process supervisor lifecycle fakes;
- coordinator races and cancellation;
- compatibility compiler/no-op behavior;
- stale scan rejection.

### Layer 4: disposable runtime integration

Only when separately authorized:

- cold/warm session fingerprint;
- sync/DPI/Retina transitions;
- compatibility/AppDefaults verification;
- exact target processes and Stop;
- bounded logs and no credentials;
- runtime capability repair.

### Layer 5: packaged/live acceptance

- actual Secunda product path;
- user-owned Steam authentication;
- exact selected display/resolution;
- presentable window;
- rendered nonblack advancing output;
- audio and input;
- requested gameplay journey;
- clean Stop and next-game isolation;
- signed/notarized quarantined clean-Mac gate for recipient release.

Passing one layer does not imply the next.

## Cross-game contamination matrix

Required sequences should include:

1. Skyrim -> Insurgency -> Skyrim.
2. Angels Fall First -> Battlefront II Classic -> Angels Fall First.
3. Supreme Commander -> Forged Alliance -> Supreme Commander.
4. Black Ops II Campaign -> Multiplayer -> Zombies.
5. Native-voice game -> builtin-voice game -> native-voice game.
6. DXVK game -> WineD3D game -> DXVK game.
7. Native-pixel/DPI mode -> standard Retina mode -> native mode.
8. Diagnostics on -> whole-space cold stop -> diagnostics off.
9. Fast sync on -> request off while active -> stop -> next cold launch.
10. Install/verify request while another game owns the bottle.
11. Recovery force-stop -> known-good game launch.
12. Warm Steam -> game requiring a changed session fingerprint.

For every hop capture:

- source/runtime/package ID;
- requested and applied session fingerprint;
- complete managed registry/AppDefaults state;
- process inventory and exact managed identities;
- launch arguments/policy digest;
- configuration hashes;
- display and window observation;
- render/audio/input acceptance status;
- stop outcome;
- log byte counts;
- evidence that unrelated state was unchanged.

## Performance verification matrix

| Benchmark | Baseline/candidate requirement |
|---|---|
| Initial useful UI | >=5 runs; p50/p95/p99/max |
| Library refresh | cold/warm plus unchanged refresh; I/O and assignment counts |
| Launch orchestration | >=5 cold and warm runs; phase/helper counts |
| Monitor idle/play | 10 minutes each; CPU/wakeups/writes/overlaps |
| Process lifecycle | repeated race/timeout/cancel/overflow suite |
| Compatibility | cold/changed/no-op with registry verification |
| Frame impact | identical save/route/display/fidelity/power/thermal capture |
| Shader cache | separate cold/warm and instrumented/clean runs |
| Package/runtime | size, manifest entries, verification time, acceptance |

## Rollback discipline

- Keep a legacy forwarding adapter until the new authority is accepted.
- Never delete legacy settings/state during the migration release.
- Preserve pre-mutation receipts and backups.
- One shared behavior change per change set.
- Runtime experiments receive a distinct runtime ID and cannot overwrite the accepted runtime artifact.
- Display/session experiments are disabled by default and exact-process gated.
- If cross-game verification fails, restore the previous known-good shared behavior rather than adding a second silent special case.

## Risk register

| Risk | Control |
|---|---|
| Dirty work mixed into refactor | Phase 0 classification/checkpoints; inspect overlap before changes |
| Actor reentrancy race | Generation validation after every await |
| Warm Steam contamination | Neutral baseline plus trusted session fingerprint and quiet transition |
| Broad process kill | Exact managed identity for normal Stop; recovery separate |
| Settings data loss | Staged versioned migration, `.previous`, receipts, retained legacy |
| Save/cache misclassification | Explicit manifest, unknown preserve-only |
| Silent resolution substitution | Requested/effective display plan and explicit adjustment reason |
| False-positive Running | Exact stable process plus graphical health milestone |
| Resource bundle omitted | Compiled profiles initially; packaging gate before resources |
| Runtime provenance drift | Canonical spec generates build/provenance/SBOM |
| Optimization regresses games | Isolated A/B plus contamination matrix and rollback |
| Excessive abstraction | Six targets, closed recipes, effect-boundary protocols only |

## Definition of done

- One executable, one shared runtime, one physical bottle.
- Adding an ordinary game changes only GameSupport, registration, and fixtures.
- No concrete game IDs in shared runtime/application/UI logic.
- Complete desired compatibility state prevents cross-game residue.
- Every mutation passes through one coordinator.
- Stop reliably invalidates and drains in-flight work.
- Normal process control uses exact identities.
- Settings/state ownership is versioned, manifest-backed, and recoverable.
- No view performs I/O and unchanged scans publish nothing.
- No-op compatibility spawns no helpers.
- Process sampling uses one helper at most and host scans never overlap.
- Running status cannot be established by process existence alone.
- Runtime build, provenance, SBOM, capabilities, and payload derive from one spec.
- Package and live acceptance remain distinct and truthful.
- Performance budgets and cross-game sequences pass without fidelity regression.

