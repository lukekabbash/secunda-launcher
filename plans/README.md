# Secunda architecture and performance plans

Status: planning only. These documents record a read-only source audit performed on 2026-08-09. They do not claim that any proposed architecture, fix, optimization, test, package, or runtime change has been implemented.

The product north star is one Secunda application, one shared Wine runtime, one physical bottle, one Steam space, and strongly isolated game definitions. Games describe their requirements through validated immutable data and pure plans. Bottle mutation remains centralized.

## Reading order

1. [Current architecture audit](01-current-architecture-audit.md)
2. [Target architecture](02-target-architecture.md)
3. [Bottle session, process, and state ownership](03-bottle-session-and-state.md)
4. [Performance plan](04-performance-plan.md)
5. [UI modularity plan](05-ui-modularity-plan.md)
6. [Runtime build and provenance plan](06-runtime-build-and-provenance.md)
7. [Migration and verification plan](07-migration-and-verification.md)
8. [Decision log and execution backlog](08-decision-log-and-backlog.md)

## Non-negotiable invariants

- Keep one physical `WINEPREFIX` unless evidence proves isolation cannot be achieved inside it.
- Keep one shared runtime by default. Title-specific runtime behavior must be gated to exact declared processes.
- A game definition describes behavior; it does not execute processes, perform I/O, mutate registry state, or publish UI state.
- One bottle coordinator owns every mutating operation: initialization, install, uninstall, verification, launch, stop, recovery, and shared compatibility transitions.
- Steam runs with a title-neutral session. A warm Steam process must not silently carry one game's environment into another game.
- Explicit display and resolution choices remain explicit. Requested and effective geometry are recorded separately; no silent fitting is presented as the user's selection.
- Process existence is not graphical launch acceptance. Handoff, stable process, presentable window, rendered output, audio, input, and gameplay are distinct evidence levels.
- Saves, settings, backups, caches, logs, and shared capabilities have explicit ownership domains.
- No optimization weakens provenance, package integrity, containment, cancellation, rollback, or cross-game acceptance.
- No flag-day rewrite. Every migration stage retains a runnable and reversible intermediate state.

## Audit boundaries

The audit used repository reads only. It did not:

- edit product code before this plans folder was requested;
- run a build or test suite;
- package or sign the application;
- launch Secunda, Wine, Steam, or a game;
- restart or manipulate a live process;
- write settings or bottle state;
- execute the provenance verifier.

Current runtime and game performance evidence quoted by these plans comes from checked-in project documentation. Proposed budgets are contracts to calibrate, not measurements of the current build.

## Working-tree warning

At the time of inspection, the repository contained 39 modified tracked files, 22 untracked files, and an approximate diff of `+3819/-808`. Those changes span UI, profiles, process/runtime behavior, patches, provenance, packaging, and documentation. Phase 0 therefore preserves and classifies the current work before moving responsibilities or files.

