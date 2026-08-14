# UI modularity plan

## Diagnosis

The current UI observes one broad `LauncherViewModel`. Any published-property mutation invalidates every mounted observer, including:

- process snapshots;
- complete settings value replacement;
- global activity and progress;
- navigation and alerts;
- one game's status changing inside the complete launcher snapshot.

Recomputation is costly because view-facing paths can perform synchronous filesystem, installation, DLC, profile, artwork, or log work.

Global presentation state also leaks meaning:

- one game's operation can show spinners on unrelated cards;
- one game's setup rail can appear after navigating to another game;
- every game detail can show the same global activity list;
- UI `isBusy` is asked to enforce bottle exclusivity.

The solution is not another large game-detail view model. Canonical state belongs to application/runtime authorities; the UI observes small stable projections.

## Target store architecture

### Root and stable registries

| Store | Owns |
|---|---|
| `LauncherStore` | Root composition, high-level subscriptions, immutable launcher state projection |
| `LauncherNavigator` | Typed current route only |
| `AlertCenter` | One typed app-level alert |
| `LauncherStatusStore` | Host/runtime/bottle/Steam/disk/power presentation |
| `GameStoreRegistry` | Stable per-`GameID` status and settings stores |
| `GroupSummaryStore` | One group's card/sidebar projection |
| `SessionPresentationStore` | Idle/preparing/running/stopping and active game identity |
| `OperationPresentationStore` | Operation ID, scope, kind, progress, cancellation policy |
| `ActivityFeedStore` | Bottle/group/game-scoped events |
| `ProcessListStore` | Recovery rows used only by Settings |
| `SupportStore` | Cached report and explicitly loaded log excerpt |
| `ArtworkModel` | One artwork identity's loading/result state |

These are presentation stores, not one service graph per game.

### Per-game status value

```swift
struct GameStatusState: Equatable, Sendable {
    let installation: InstallationState
    let saves: SaveSummary
    let addOns: [AddOnState]
    let profileReadiness: ProfileReadiness
    let artworkSources: ArtworkSources
}
```

`apply(_:)` guards `next != state` before assignment. An unchanged scan produces no observable mutation.

Store instances are constructed once by typed ID in `LauncherAssembly` and retained. Never instantiate observable game stores inside `ForEach` or `body`.

## State reduction

An off-main library scan returns one immutable `LibraryScanResult`. A main-actor reducer diff-applies it to:

- global status only if changed;
- affected game stores only;
- affected group summaries only;
- no presentation store for unchanged values.

Stale scan results carry a scan sequence and cannot overwrite a newer application state revision.

## Per-game settings

Keep `GameSettings` as a domain value. `GameSettingsStore` owns immediate UI edits for one game; `SettingsRepository` owns persistence.

Requirements:

- stable `ChoiceID`, never visible label identity;
- launch choices stored separately from Lua tuning choices;
- stable `ForEach` IDs;
- short write coalescing;
- revision ordering;
- explicit dirty/error state;
- flush before launch and lifecycle/migration boundaries;
- failed persistence does not silently revert or overwrite the UI value.

## Operations

Replace global booleans with a scoped value:

```swift
struct OperationViewState: Equatable, Sendable {
    let id: OperationID
    let scope: OperationScope
    let kind: OperationKind
    let progress: OperationProgress?
    let cancellation: CancellationPolicy
}
```

Effects:

- Game A displays Game A's progress.
- Other games can be unavailable because the bottle lease is held without showing Game A's spinner.
- Bottle-wide setup displays bottle-wide progress.
- Stop sends `cancelLaunchAndStop`; it does not manually clear presentation fields or directly manipulate a raw task.
- Install, uninstall, verify, DLC, launch, stop, and recovery share one operation authority.

## Navigation and presentation ownership

Typed route:

```swift
enum LauncherRoute: Hashable {
    case library
    case game(GameGroupID)
    case settings
}
```

Rules:

- Runtime/domain services never change navigation.
- Application actions return typed outcomes such as `requiresSetup`.
- Shell-level code translates outcomes into route/sheet decisions.
- Root alerts use typed errors and recovery actions, not an arbitrary string on the bottle service.
- Hover and entrance animation remain local `@State`.
- Screen-owned sheets/dialogs use one optional destination enum rather than independent booleans.
- Durable selected group component belongs in a `GroupSelectionStore`, not duplicated local state.

## Dependency assembly

Move live construction out of `LauncherViewModel.live()` into `LauncherAssembly`.

`LauncherAssembly` is the only place aware of concrete live implementations. Feature stores receive narrow capabilities:

- library scanning/commands;
- settings repository plus one definition;
- game commands plus session presentation;
- process recovery monitoring/commands;
- diagnostics provider;
- clipboard/workspace/display adapters.

No universal environment object or service locator passes through all views. More than roughly five unrelated constructor dependencies is evidence that a coordinator or projection is missing.

## Game-detail feature split

```text
Features/GameDetail/
  GameDetailScreen.swift
  GameDetailSelectionStore.swift
  GameHeroSection.swift
  GameActionSection.swift
  GameStatusSection.swift
  DisplaySettingsSection.swift
  GraphicsSettingsSection.swift
  AddOnsSection.swift
  SavesSection.swift
  GameSettingsBindings.swift
```

Responsibilities:

- `GameDetailScreen`: select stable stores and compose sections.
- `GameHeroSection`: immutable presentation plus one artwork model.
- `GameActionSection`: primary action, stop, refresh, menu, scoped operation/session state.
- `GameStatusSection`: environment, selected game status, scoped activity.
- `DisplaySettingsSection`: display fields and profile readiness.
- `GraphicsSettingsSection`: quality and tuning fields.
- `AddOnsSection`: immutable rows and install intent.
- `SavesSection`: counts and backup intent.
- `GameSettingsBindings`: SwiftUI binding adapter around one settings store.

No runtime logic belongs in these views.

## Typed adaptable fields

Use a closed field schema:

```swift
enum GameSettingField: Equatable, Sendable {
    case displayMode(DisplayModeField)
    case resolution(ResolutionField)
    case fieldOfView(IntegerField)
    case verticalSync(BooleanField)
    case choice(ChoiceField)
    case fixedFramePacing(FramePacingField)
    case nativeVoiceAudio(BooleanField)
}
```

Render with an exhaustive `@ViewBuilder switch`.

Do not use:

- `AnyView` registries;
- reflection;
- game-ID UI switches;
- dynamic plugin views;
- stringly typed arbitrary controls.

When a new game needs a genuinely new capability, add one reusable typed field capability.

## Shared UI modules

```text
Shared/Sections/
  FlatSection.swift
  SectionEmptyState.swift
  SettingRow.swift
  ChoiceSettingRow.swift
  ToggleSettingRow.swift
  StepperSettingRow.swift
  MetricView.swift

Shared/Status/
  StatusStrip.swift
  StatusGlyph.swift
  ActivityList.swift

Shared/Progress/
  ProgressBar.swift
  SetupRail.swift

Shared/Artwork/
  GameArtworkView.swift
  ArtworkModel.swift
```

Split the current catch-all `Components.swift` by these cohesive groups.

## Other feature splits

```text
Features/Shell/
  LauncherShellView.swift
  LauncherRouteView.swift
  LauncherSidebar.swift
  SidebarGameRow.swift
  GlobalAlertPresenter.swift

Features/Library/
  LibraryScreen.swift
  LibrarySection.swift
  GameCard.swift
  LibraryDestination.swift

Features/Settings/
  LauncherSettingsScreen.swift
  PerformanceSettingsSection.swift
  RuntimeSettingsSection.swift
  ProcessRecoverySection.swift
  ArtworkSettingsSection.swift
  CompatibilitySettingsSection.swift
  DiagnosticsSettingsSection.swift
  SupportSection.swift
  AboutSection.swift
```

A process-list update must not regenerate support content, reread logs, reload artwork, or recompute static About content.

## Artwork repository

Current global artwork revision causes all image views to invalidate when any key loads or fails.

Target:

```swift
actor ArtworkRepository {
    func image(for request: ArtworkRequest) async throws -> PreparedArtwork
}
```

Cache key includes:

- artwork identity;
- all candidate-source fingerprints;
- target pixel size;
- crop policy;
- processing version.

Contracts:

- decode/downsample off-main with ImageIO;
- cost-limited `NSCache`;
- cancellation flows from view `.task` through the repository;
- one `ArtworkModel` observes one key;
- cached/pre-rendered blurred background;
- failure TTL or file-change invalidation;
- loading artwork A publishes nothing to artwork B.

## Main-actor policy

The main actor may:

- reduce immutable scan/event results;
- assign changed presentation state;
- manage navigation, alerts, and visual bindings;
- call AppKit through narrow adapters where required.

The main actor may not:

- scan files/directories;
- parse Steam manifests;
- start or await processes;
- read logs;
- hash runtime/capability files;
- decode/downsample images;
- discover saves/backups/DLC;
- resolve profile readiness from disk.

Target main-actor slice: <=4 ms P95.

## UI migration sequence

1. Add presenter/reducer characterization tests for current actions, group state, settings defaults, setup journey, and progress copy.
2. Mechanically extract view sections while retaining the legacy view model.
3. Introduce typed game/group/operation IDs, navigator, and alert center.
4. Move live construction into `LauncherAssembly`.
5. Introduce a single-flight off-main scanner producing complete display-ready results.
6. Add stable game stores and migrate library cards/sidebar first.
7. Add group selection and per-game settings stores; migrate detail sections incrementally.
8. Introduce scoped session/operation/activity presentation.
9. Split Settings into narrow stores and load support/log content only on explicit demand.
10. Replace global artwork revision.
11. Remove `LauncherViewModel` only after no view consumes it.

## UI acceptance gates

- An unchanged process sample performs zero UI assignments.
- Artwork A invalidates only artwork A.
- One game setting changes only the relevant control/section and produces one coalesced persistence write.
- Game A progress never appears on Game B.
- Process-list changes do not reread logs or regenerate support reports.
- No `body` or presentation computed property performs I/O.
- Scans are single-flight and stale results cannot publish.
- Active gameplay sharply reduces nonessential scanning/artwork work.
- Adding an ordinary game requires no shell, grid, sidebar, or detail source change.
- Every operation has typed scope, ownership, cancellation, and error routing.

## File and function rules

- Screen composition target: 80–160 lines.
- Feature store/presenter target: 120–250 lines.
- Reusable leaf view target: 30–120 lines.
- Any file over 300 lines receives a cohesion review.
- Ordinary function target: under 25 executable lines.
- `body` and linear orchestration target: under 40–50 lines with at most three nesting levels.
- One observable authority per file.
- A view observes the smallest store that can change its pixels.
- Comments explain visual/state authority and non-obvious constraints, not implementation narration or outside IP.
