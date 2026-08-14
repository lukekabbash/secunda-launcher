# Bottle session, process, and state ownership

## Core ownership rule

The actor follows the shared mutable resource.

Secunda has one physical bottle, so it has one `BottleSessionCoordinator`. Games are immutable `Sendable` definitions and plans. They are not actors and do not own services.

The coordinator is the only authority allowed to mutate:

- bottle initialization state;
- Steam installation/client state;
- session-wide compatibility;
- active game identity;
- install/uninstall/verify operations;
- launch and stop state;
- recovery state;
- the session ledger.

UI disabled-state logic is only a projection. It is never the enforcement boundary.

## Compatibility ownership classes

### Bottle capability: monotonic

Examples:

- installed DXVK payload;
- installed native audio payload;
- runtime compatibility schema;
- managed helper availability.

These may be installed or repaired at a quiet boundary. A game plan declares requirements but does not own installation.

### Wineserver/session-wide

Examples:

- requested/applied fast synchronization;
- `LogPixels`;
- Retina mode;
- selected display geometry;
- session environment retained by Steam/Wine;
- diagnostics session policy.

These values require one authoritative session fingerprint. They cannot be treated as independent per-game preferences while a warm wineserver continues running.

### Executable-scoped

Examples:

- AppDefaults DLL rules;
- Mac-driver decoration;
- supported per-app renderer settings;
- exact executable compatibility gates.

All executable aliases declared by the game profile must receive consistent state.

### Process-scoped

Examples:

- Steam application identity;
- direct-launch arguments;
- frame cap and approved feature flags;
- managed cache/log paths when the launch strategy can actually inject them.

A warm Steam process does not receive a newly changed parent environment. The planner must not pretend process-scoped injection is available when the selected launch strategy cannot provide it.

### Game-file scoped

Examples:

- INI;
- KeyValues;
- Lua preferences;
- save files;
- game-owned logs and caches.

These are addressed through validated state manifests and profile recipes.

## Complete desired state

```swift
public struct BottleCompatibilityPlan: Equatable, Sendable {
    public let requiredCapabilities: Set<BottleCapability>
    public let dllOverrides: [DLLOverride]
    public let logPixels: Int
    public let retinaMode: Bool
    public let renderer: WineRenderer
    public let appDefaults: [AppDefaultMutation]
    public let processEnvironment: [ApprovedEnvironmentOverride]
}
```

For every Secunda-owned registry value, the plan contains an explicit operation:

```swift
enum RegistryMutation {
    case set(RegistryValue)
    case delete(RegistryValueAddress)
    case restoreNeutral(RegistryValueAddress)
}
```

There is no implicit "leave previous value alone" for managed state.

The compatibility fingerprint includes:

- bottle ID and generation;
- runtime ID;
- profile schema version;
- executable aliases;
- full desired managed-state digest;
- session-wide display/sync tuple.

No-op reconciliation spawns no helpers and performs no writes.

## Session state machine

```swift
public enum BottleSessionState: Equatable, Sendable {
    case cold
    case steamOnly(SteamSession)
    case preparing(OperationID, GameID)
    case launching(GameSession, GameLaunchStage)
    case running(GameSession)
    case stopping(GameSession)
    case recovering(RecoveryOperation)
    case failed(SessionFailure)
}
```

The state carries identities, not only booleans. `isBusy`, `anyGameActive`, and progress strings become derived presentation values.

## Reentrancy and generation contract

Swift actors are reentrant at every `await`. Serialization at method entry is insufficient.

Required algorithm:

1. Validate the command against current state.
2. Reserve an `OperationID` and increment/reserve a bottle generation.
3. Publish the initial typed phase.
4. Perform one awaited external step.
5. Re-enter the actor and verify operation plus generation.
6. Commit that step or discard its stale result.
7. Repeat until terminal state.

Stop behavior:

1. Increment the generation immediately.
2. Mark the active operation cancelled/stopping.
3. Cancel owned helper tasks.
4. Stop exact managed game processes.
5. Wait for or force bounded bottle quiescence.
6. Restore the neutral profile only when quiet.
7. Persist terminal session outcome.

A stale launch may log its superseded result but cannot mutate compatibility, publish Running, or reopen the game.

## Operation admission

Every mutating command uses one admission function:

```swift
func begin(_ command: BottleCommand) throws -> OperationLease
```

Commands include:

- initialize bottle;
- install Steam;
- install/uninstall/verify game;
- install/uninstall add-on;
- launch game;
- stop game space;
- repair capability;
- rebuild bottle;
- explicit recovery force-stop.

Read-only snapshots may run concurrently if they join the monitor's single-flight scan and cannot publish stale state.

## Process supervisor

### Responsibilities

`ProcessSupervisor` is an actor owning every launcher-created helper and managed long-lived process.

```swift
public struct ProcessCommand: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let currentDirectory: URL?
    public let role: ProcessRole
    public let output: ProcessOutputPolicy
    public let timeout: Duration?
}
```

The public command type may eventually replace raw environment/argument strings with approved typed values at sensitive boundaries.

### Lifecycle

```text
configured -> registered -> started -> terminating -> exited
```

Contracts:

- Register the process record before fast termination can race its handler.
- Resolve launch failure, exit, timeout, cancellation, and forced termination exactly once.
- Race exit against one structured timeout task.
- Cancel the timeout immediately when exit wins.
- Always drain bounded output before final delivery.
- Remove the active record after terminal delivery.
- Retain zero terminal records unless a bounded diagnostic history explicitly owns a copy.

### Cancellation policy by role

| Role | Caller cancellation behavior |
|---|---|
| Probe/helper | Terminate, bounded grace, revalidate, force if required, drain |
| Capability installer | Terminate unless the step has committed an atomic replacement; reconcile on next run |
| Steam client | Detach after committed spawn; only explicit Stop owns termination |
| Game process | Detach after committed spawn; only explicit Stop owns termination |
| Recovery process | Controlled only by recovery operation identity |

Use `withTaskCancellationHandler`. A cancelled Swift task must never leave an unowned helper or an undelivered continuation.

### Managed identity

PID alone is insufficient.

```swift
public struct ManagedProcessIdentity: Hashable, Sendable {
    public let launchID: LaunchID
    public let pid: Int32
    public let startIdentity: ProcessStartIdentity
    public let executable: URL
    public let role: ProcessRole
    public let bottleID: BottleID
    public let bottleGeneration: BottleGeneration
    public let gameID: GameID?
    public let sessionID: SessionID?
}
```

Before a force signal, revalidate PID, start identity, executable/provenance, and bottle/session ownership.

### Output policies

```swift
public enum ProcessOutputPolicy: Sendable {
    case discard
    case boundedCapture(limit: Int)
    case rotatingLog(LogScope)
}
```

- Capture limits are mandatory and positive.
- Overflow fails closed.
- Diagnostics-off ordinary play does not produce verbose renderer/Wine logs.
- Output sinks remain open for the process lifetime instead of reopening/seeking on every write.

## Bottle process monitor

`GameSpaceProcessMonitor` owns:

- exact known managed handles;
- one indexed Windows process snapshot;
- one host reconciliation in flight;
- snapshot freshness and sequence;
- subscriber delivery;
- cached executable provenance.

Cost ladder:

1. Supervised process exit events.
2. Known PID/start-identity checks.
3. One indexed Windows process sample when required.
4. Command text/prefix filtering.
5. `proc_pidpath` for unresolved likely Wine candidates only.
6. Cached runtime provenance by resolved path and filesystem identity.
7. Slow full recovery reconciliation.

Broad all-Secunda provenance matches remain visible in Settings/Recovery but never become normal per-game kill authority.

## Bottle metadata and ledger

Persist bottle metadata after initialization:

- stable `BottleID`;
- `BottleGeneration`;
- canonical Windows user selected once after `wineboot -w`;
- runtime compatibility version;
- installed capability inventory.

Keep the existing physical bottle path initially. Identity becomes metadata-backed; no risky directory rename is required.

### Session ledger

Persist bounded privacy-safe facts:

```text
bottleID
bottleGeneration
runtimeID
sessionID
operationID
launchID
gameID
stateDomainID
Steam app ID
requested and applied sync
compatibility-plan digest
display/session fingerprint
managed process identities
phase timestamps
terminal outcome
```

Do not persist:

- credentials;
- raw environment dumps;
- complete command lines with private paths/tokens;
- unbounded Wine output;
- account identifiers not required for recovery.

On application start, a ledger is a recovery hint. Live process evidence remains authoritative.

## Session fingerprint

The canonical digest input contains:

- runtime ID;
- bottle ID/generation;
- requested and applied fast-sync state;
- DPI and Retina mode;
- selected display ID, origin, point/pixel dimensions, and scale;
- effective game resolution/mode;
- cursor policy;
- diagnostic/session environment policy;
- compatibility schema and desired-state digest.

Use a canonical byte representation and a strong deterministic digest. This is identity/integrity metadata, not a password hash.

## Game-state manifest

```swift
public struct GameStateManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let revision: Int
    public let gameID: GameID
    public let stateDomainID: StateDomainID
    public let locations: [GameStateLocation]
    public let backupPolicy: BackupPolicy
    public let resetPolicy: ResetPolicy
}
```

Managed roots may include:

- Windows user root;
- Documents;
- AppData Local/Roaming;
- Saved Games;
- installation root;
- Steam userdata;
- Secunda-managed state root.

Each location declares:

- safe relative path;
- role: save, configuration, cache, log, cloud, opaque;
- durability: authoritative, reconstructable, regenerable, diagnostic, unknown;
- sharing domain;
- backup disposition;
- reset disposition;
- quiescence requirement;
- exact allowed file/directory/extension policy.

No arbitrary recursive globs. Unknown state is preserve-only.

## Logical state layout

```text
State/
  Settings/
    global.json
  Sessions/
  Migrations/
  Legacy/

GameState/<state-domain>/
  Launcher/
    settings.json
  Files/
  Caches/
    Graphics/
  Logs/
  Backups/<snapshot-id>/
    manifest.json
    payload/
  Trash/<operation-id>/

SharedState/
  Capabilities/
  Downloads/
  Logs/
```

First introduce manifests and resolvers around existing paths. Do not externalize complete Windows user directories or Steam userdata in the initial refactor.

## Settings repository

`SettingsRepository` is an actor with:

- cached current state;
- schema version;
- monotonic revision;
- serialized/coalesced writes;
- dirty/error state;
- explicit flush boundary.

Write protocol:

1. Validate the new value.
2. Encode to a same-directory temporary file.
3. Decode and verify the temporary file.
4. Preserve a `.previous` recovery copy.
5. Atomically rename.
6. Record the committed revision.

Decode failure:

- preserve/quarantine the invalid document;
- surface a typed error;
- offer an explicit recovery/default action;
- never silently overwrite it with defaults.

Persist stable choice IDs and preserve unknown option IDs for forward/backward compatibility.

Requested fast sync is a preference. Applied fast sync belongs to session state and the ledger.

## Settings migration

Proposed path:

```text
v0: unversioned flat settings
v1: versioned current-shape settings
v2: global plus state-domain split
```

Migration protocol:

- stage outputs outside the authoritative location;
- validate and hash every staged document;
- write a migration receipt;
- atomically promote;
- retain the legacy input for at least one accepted release cycle;
- support resume after interruption;
- never partially delete the source.

## Backup, restore, and reset verbs

Expose exact operations rather than an ambiguous "reset game":

- clear regenerable caches;
- reset generated configuration;
- create backup;
- restore backup;
- remove declared local state;
- request Steam verify/uninstall;
- repair shared capabilities;
- rebuild the bottle.

Safety contracts:

- Cache clear never touches saves or authoritative configuration.
- Steam uninstall does not imply removal of local state, launcher settings, or backups.
- Restore creates a pre-restore snapshot.
- Reset/delete uses managed trash with an operation receipt where practical.
- Cloud-backed state is modified only under a proven policy; otherwise exclude it.
- Bottle rebuild preserves accepted game-state locations and unknown preserve-only data.

## Event delivery

```swift
public struct BottleEvent: Equatable, Sendable {
    public let operationID: OperationID
    public let scope: OperationScope
    public let gameID: GameID?
    public let phase: OperationPhase
    public let timestamp: ContinuousClock.Instant
}
```

Use one bounded `AsyncStream` subscription from the application controller. UI projections receive typed state, not runtime callbacks.

## Required invariants

- At most one bottle mutation lease exists.
- Every awaited mutation verifies its operation and generation before commit.
- A cancelled launch cannot publish Running or reopen a title.
- Steam is either cold, neutral, or represented by an exact trusted session fingerprint.
- Managed registry state is complete, not incremental guesswork.
- Normal Stop targets exact managed identities only.
- Broad recovery authority is explicitly named and separately surfaced.
- A settings failure cannot reset another game's settings.
- A state-domain backup cannot be counted as another domain's backup.
- Unknown state is preserved.
- Every terminal operation produces a bounded outcome.

