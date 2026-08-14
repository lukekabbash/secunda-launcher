# Decision log and execution backlog

## Accepted architectural decisions

### D-001: preserve one physical bottle

Decision: keep one `WINEPREFIX` and one Steam space.

Reason: the user explicitly wants all supported games in the same bottle. Isolation is achieved through typed definitions, complete desired state, exact process identity, session fingerprints, and state domains.

Revisit only if evidence proves a requirement cannot be safely represented inside one bottle.

### D-002: one coordinator per bottle, not one actor per game

Decision: `BottleSessionCoordinator` owns shared mutation. Game definitions are immutable `Sendable` values.

Reason: actors should follow shared mutable resources. Per-game actors would not serialize registry, wineserver, Steam, or bottle transitions.

### D-003: modular monolith with six static targets

Decision: Domain, GameSupport, Runtime, Application, UI, and executable composition.

Reason: meaningful one-way dependency boundaries without a target per game or a dynamic plugin system.

### D-004: compiled Swift game definitions initially

Decision: one small definition file per game/family inside `SecundaGameSupport`.

Reason: closed typed effects, compiler validation, and current packaging simplicity. Resource-backed leaf data is deferred until packaging copies and attests resource bundles.

### D-005: pure plan, effectful executor

Decision: `GameLaunchPlanner` is deterministic and performs no I/O. Runtime/coordinator execute its plan.

Reason: makes title behavior testable without Wine and keeps side effects at the bottle boundary.

### D-006: complete compatibility desired state

Decision: every Secunda-owned key has explicit set/delete/neutral behavior.

Reason: incremental writes cannot reliably prevent previous-game leakage.

### D-007: separate identity domains

Decision: `GameID`, `GameGroupID`, `StateDomainID`, and `ProcessIdentityDomainID` are distinct.

Reason: UI grouping, launch selection, save ownership, and shared executable identity are different concepts.

### D-008: explicit display truth

Decision: persist requested and effective display geometry separately with display identity/scale/DPI/Retina/cursor policy.

Reason: a selected resolution cannot be silently fitted or presented inaccurately.

### D-009: stable process plus graphical health before Running

Decision: process existence alone is insufficient. Graphical games require their explicit window-health contract.

Reason: process persistence can coexist with a crash dialog, invisible surface, black output, or unusable input.

### D-010: normal Stop and broad recovery are separate authorities

Decision: normal Stop targets exact current-session identities; all-Secunda provenance scanning appears only in a separately named recovery path.

Reason: broad recovery visibility must not become normal kill authority.

### D-011: versioned split settings and manifest-backed state

Decision: global settings, per-state-domain launcher settings, session ledger, and game-state manifests have separate owners.

Reason: prevents one malformed game document or ambiguous backup/reset operation from affecting unrelated games.

### D-012: canonical runtime specification

Decision: one runtime spec generates build inputs, provenance, SBOM, capability manifest, and player projection.

Reason: current duplicated patch/version/hash authority can drift.

### D-013: performance claims require isolated evidence

Decision: architecture improvements may claim launcher latency/CPU/wakeup reductions when measured; FPS claims require controlled frame captures.

Reason: modularity alone does not raise FPS, and current evidence is title/scene-specific.

## Rejected approaches

### R-001: one bottle per game

Rejected because it violates the requested product model and duplicates Steam/runtime state.

### R-002: one service or actor graph per game

Rejected because it fails to serialize shared bottle/session state and creates repeated infrastructure.

### R-003: one Swift target per game initially

Rejected because profiles should be small data modules; many targets add API/build ceremony without enough value.

### R-004: dynamic plugin loader

Rejected because it adds loading, schema, signing, compatibility, and arbitrary-effect risks that the current product does not need.

### R-005: universal arbitrary configuration/effect DSL

Rejected in favor of four explicit profile recipes and closed capability enums.

### R-006: service locator or universal environment object

Rejected because dependencies and ownership become hidden.

### R-007: title-specific SwiftUI branches

Rejected in favor of generic typed fields and reusable feature sections.

### R-008: treating process existence as launch acceptance

Rejected because it produces false-positive Running states.

### R-009: global renderer/VSync/scheduling changes based on one capture

Rejected because current evidence is not cross-game and disabling sync was slightly worse in the recorded case.

### R-010: direct player-runtime deletion

Rejected. RuntimeSDK/PlayerRuntime separation must be allowlisted, verified, and accepted across games.

## Deferred decisions

### F-001: resource-backed leaf profiles

Prerequisites:

- stable profile schema;
- packaging copies SwiftPM bundles;
- bundle resources covered by signing/provenance/verification;
- unknown schema failure behavior.

### F-002: long-lived Windows process watcher

Prerequisite: indexed one-helper sampling remains a measured problem after monitor optimization.

### F-003: persistent runtime integrity receipt

Prerequisite: immutable Developer-ID-signed/notarized runtime artifact with receipt bound to exact code-signature/build/manifest identity.

### F-004: Game Mode design

Prerequisite: an isolated implementation can visibly prove the translated child receives Game Mode, with no title regression.

### F-005: narrower AVRT behavior

Prerequisite: thread/task-aware evidence demonstrates current global time-critical promotion helps or harms specific workloads.

### F-006: externalizing game state from the bottle

Prerequisite: one location has a proven ownership/backup/rollback benefit and passes live acceptance. Do not relocate whole user trees initially.

### F-007: cache namespace changes

Prerequisite: measured executable collision, repair-survival, or diagnostic isolation need; cold/warm stutter evidence included.

## Confirmed findings backlog

### P0 — truth and shared-state correctness

#### B-001: reconcile runtime patch provenance

Deliverable:

- canonical list includes every applied patch;
- current hashes match;
- verifier rejects missing and extra patches.

Gate: repository, staged runtime, embedded package provenance, and build recipe agree.

#### B-002: complete native-audio desired state

Deliverable:

- `xactengine3_7` and all managed DLL keys have explicit native/builtin/delete behavior;
- transition fixtures cover native -> builtin -> native.

Gate: no residue after cross-game transitions.

#### B-003: namespace legacy and current backups

Deliverable:

- validated state-domain namespace;
- manifest per backup;
- explicit legacy-unprefixed classification.

Gate: each game/domain counts only its own backups.

#### B-004: make Stop invalidate real launch work

Deliverable:

- bottle generation/operation identity;
- cancellation handler for helpers;
- explicit managed-handle Stop for committed processes.

Gate: no late Running/handoff after Stop.

#### B-005: establish title-neutral Steam profile

Deliverable:

- complete neutral managed state;
- trusted session fingerprint;
- quiet transition rules.

Gate: warm Steam cannot silently inherit an incompatible game session.

## Architecture backlog

### P1 — domain and definitions

#### B-101: add validated boundary IDs and safe relative paths

Small scope: Domain-only values and tests; no production authority change.

#### B-102: add composed game definition and catalog validation

Small scope: types, validation, structured errors.

#### B-103: add legacy descriptor adapter

Small scope: current callers receive equivalent values from the new catalog.

#### B-104: migrate first simple game definition

Small scope: one definition, registration, fingerprint fixture.

#### B-105: add structural concrete-game-ID boundary check

Small scope: fail when IDs appear outside GameSupport, migrations, or tests.

### P1 — configuration

#### B-120: writable INI pure editor

#### B-121: existing-only INI pure editor

#### B-122: quoted KeyValues pure editor

#### B-123: bounded Lua preferences pure editor

#### B-124: contained atomic profile-plan executor

Each editor is a separate focused change with idempotence/byte fixtures.

### P1 — bottle/process authority

#### B-140: coordinator wrapper around legacy launch facade

#### B-141: operation admission and generation validation

#### B-142: structured ProcessSupervisor

#### B-143: indexed one-helper Windows process snapshot

#### B-144: single-flight exact bottle monitor

#### B-145: separately scoped broad recovery scanner

#### B-146: complete compatibility compiler/fingerprint/import

#### B-147: bounded launch outcome recorder

### P1 — settings/state

#### B-160: state-domain manifests

#### B-161: versioned settings repository actor

#### B-162: v0/v1/v2 staged migration

#### B-163: manifest-backed backup/restore/reset

#### B-164: session ledger and recovery validation

## Performance backlog

### P1 — low-risk high-return

#### B-201: baseline signposts and counters

No behavior optimization before this measurement layer.

#### B-202: collapse Windows process queries

Acceptance: <=1 Wine helper per sample with identical process results.

#### B-203: monitor single-flight and stale-result rejection

Acceptance: zero overlap; unchanged sample publishes nothing.

#### B-204: monitor cost ladder and active/idle cadence

Acceptance: >=20 percent reduction in monitor subprocesses/wakeups/CPU without stale Stop state.

#### B-205: compatibility no-op fast path

Acceptance: zero helpers and writes when desired state already matches.

#### B-206: Steam library index

Acceptance: directory event invalidates only affected app IDs; unchanged refresh avoids rereads.

#### B-207: runtime catalog cache

Acceptance: warm lookup <=50 ms P95; cold integrity authority preserved.

#### B-208: capability validation receipts

Acceptance: unchanged validated payload avoids full reread; metadata change invalidates.

### P2 — UI and footprint

#### B-220: off-main complete library scanner

#### B-221: stable game stores and diff reducer

#### B-222: scoped operation/session/activity stores

#### B-223: artwork repository/downsampling/cache

#### B-224: narrow Settings/support stores

#### B-225: move broad self-checks to test targets

#### B-226: RuntimeSDK/PlayerRuntime projection

### P3 — experiments

#### B-240: frame impact of optimized monitor

#### B-241: Game Mode eligibility experiment

#### B-242: AVRT policy experiment

#### B-243: per-title renderer/fidelity trials

#### B-244: shader-cache topology trials

Every P3 ticket requires a baseline, isolated candidate, exact runtime ID, rollback, and game matrix.

## UI backlog

### P1 — mechanical decomposition

#### B-301: split GameDetail into cohesive sections

Behavior unchanged; legacy model retained.

#### B-302: split shell/library/settings surfaces

Behavior unchanged; no new authority.

#### B-303: split catch-all Components into cohesive shared modules

### P1 — state authority

#### B-320: typed navigator and alert center

#### B-321: move composition to LauncherAssembly

#### B-322: stable GameStoreRegistry

#### B-323: per-game settings stores with stable choice IDs

#### B-324: scoped operation/session/activity projections

#### B-325: remove view-body I/O

#### B-326: replace global artwork revision

#### B-327: remove legacy LauncherViewModel facade

## Build and distribution backlog

### P0/P1

#### B-401: define `runtime-spec.json` schema and validator

#### B-402: generate patch list/provenance/SBOM from spec

#### B-403: enforce fresh canonical extraction and patch application

#### B-404: compute content-derived RuntimeID

#### B-405: generate/verify capability and player-payload manifests

#### B-406: support sealed-runtime app-only packaging

#### B-407: extend packaging before any profile resource bundles

## Recommended first implementation tranche

Keep this sequence narrow and reversible:

1. B-001 provenance reconciliation.
2. B-002 complete native-audio desired state.
3. B-003 backup namespace correction.
4. B-004 real cancellation/Stop invariant.
5. B-201 baseline instrumentation.
6. B-101 typed boundary IDs.
7. B-102 validated catalog.
8. B-103 legacy adapter.
9. B-104 one vertical game-definition slice.
10. B-202 indexed process snapshot.
11. B-203 single-flight monitoring.
12. B-205 compatibility no-op fast path.

Do not begin broad target/file movement before these contracts are stable.

## Work-item template

Each implementation item should state:

```text
Objective
Current authority and evidence
Exact scope
Non-goals
Public/internal API change
State/process/files touched
Cross-game blast radius
Migration and rollback
Pure/integration/package/live gates
Performance baseline and budget
Acceptance evidence
```

Keep one primary reason to change per item. If a change cannot be explained and rolled back independently, split it.

## Open evidence questions

1. What are current cold/warm launch phase timings and helper counts for each launch strategy?
2. How much CPU/wakeup/frame-time interference comes from the five-second host scan?
3. Which exact keys can move safely to executable-scoped AppDefaults for every alias?
4. Which runtime files in the 86.9 MB candidate set are actually loaded by package tests or supported games?
5. Can a translated child become visibly Game Mode eligible through a supported architecture?
6. Which AVRT task names are promoted, and what is their effect on render/audio scheduling?
7. Which games truly require cache namespaces, and what are cold/warm costs?
8. Which state locations are authoritative, cloud-managed, regenerable, or currently unknown?
9. What are the exact semantics and rollback needs for legacy unprefixed backups?
10. Which launch strategies can safely inject per-process cache/feature variables without contaminating warm Steam?

These questions are resolved by bounded evidence, not architectural guesswork.
