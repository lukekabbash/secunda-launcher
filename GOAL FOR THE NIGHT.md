
SECUNDA — SOURCE-ONLY SKYRIM ON APPLE SILICON

We are continuing the existing Secunda project.

This is an IMPLEMENTATION task.

Do not spend the session producing a speculative architecture document while the real system remains broken. Research only when it resolves a concrete uncertainty encountered during implementation.

FIRST ACTIONS

Inspect the existing repository and current Git state.

Preserve main exactly as the known working baseline.

Create and switch to a new branch:

source-only-secunda

Never modify, rewrite, squash, delete, or otherwise damage the known-working main history.

Inspect the existing implementation, source-runtime build scripts, patches, diagnostics, Steam/Skyrim services, and prior experimental source runtime before proposing replacements.

Establish the Goal below with /goal.

Begin implementing immediately.

/goal

/goal Build a completely free, source-based Secunda runtime for Apple Silicon that launches the user's legitimately owned Windows Steam installation path and Skyrim Special Edition without requiring, linking against, loading libraries from, redistributing, or depending at runtime on the proprietary CrossOver application. Success is verified only by an isolated source-only test path that reaches a visibly rendered Steam UI, launches Skyrim Special Edition, renders correct game graphics, produces working audio, accepts keyboard/mouse input, enters gameplay, creates/loads a save, quits, and successfully relaunches that save. Preserve the user's existing working Steam/Skyrim/CrossOver installation, saves, credentials, and main branch untouched. Use the supplied CrossOver open-source source tree/archive and other legally redistributable open-source components already available or obtainable from their authoritative sources. Between iterations, use observed logs, traces, process state, graphics behavior, minimal reproductions, source inspection, and controlled experiments to select the next highest-information implementation step. Do not abandon the Goal merely because one architecture, graphics backend, Wine configuration, patch, dependency, or hypothesis fails. Reduce failures to smaller reproducible tests and engineer alternatives from first principles. Declare a BLOCKER only when evidence demonstrates that no presently actionable implementation experiment remains under the stated constraints, and report the exact evidence plus the smallest thing that would unblock further engineering.

PRIMARY PRODUCT REQUIREMENT

The finished architecture must conceptually be:

Secunda.app→ Secunda-owned open-source compatibility runtime→ isolated Secunda Windows prefix→ Windows Steam→ Skyrim Special Edition→ macOS / Metal / Apple Silicon

NOT:

Secunda.app→ proprietary CrossOver.app→ Skyrim

The proprietary CrossOver application is forbidden as an implementation dependency and forbidden as evidence that an acceptance test passed.

Do not accidentally "solve" the project by discovering the installed CrossOver application and using its Wine binaries, DXMT/D3DMetal libraries, GPTK payload, d3dshared, apple_gptk, bottle infrastructure, or other proprietary runtime components.

The existing working CrossOver setup MAY be treated as a black-box behavioral reference for differential diagnosis when useful.

It MAY NOT contribute binaries or libraries to the source-only runtime.

Every successful acceptance test must record exactly which executable and dynamic libraries were actually loaded so we can prove the test was source-only.

EXISTING ASSETS

Take advantage of what is already on this machine.

There is already:

a working Secunda launcher implementation

an existing source-runtime build path

the supplied CrossOver source-compliance archive/source tree

Wine source

graphics/runtime-related open-source sources from that archive

existing patches and build scripts

a working Steam installation / bottle path from previous development

an installed Skyrim Special Edition copy that has already been proven to launch

known-good working Skyrim audio under the proprietary-runtime baseline

an Apple Silicon M5 Mac

Rosetta where required for x86-64 Windows software

existing diagnostics and launch infrastructure

DO NOT needlessly reinstall or redownload Skyrim merely to obtain files we already legitimately have locally.

Reuse existing Steam/Skyrim game data as read-only or cloned test input where safe.

However:

DO NOT mutate the user's working Steam installation.DO NOT mutate the user's known-working bottle.DO NOT delete or move saves.DO NOT touch Steam credentials/session material unnecessarily.DO NOT alter the user's proprietary CrossOver installation.

Create isolated Secunda source-only prefixes and test directories.

BIAS FOR ACTION

Implementation > investigation > documentation.

A useful default allocation is approximately:

75–85% implementation, compilation, instrumentation, testing, and debugging

10–20% targeted source/documentation research

<10% planning/reporting

Do not enforce those percentages mechanically; they describe the desired bias.

Research should answer questions such as:

What exact compositor/rendering path is failing?

Which DLL/API/backend produced the observed failure?

Is the failure Wine, DXVK, MoltenVK, CEF, Vulkan, Metal, Rosetta, window composition, synchronization, memory mapping, audio, or something else?

What upstream implementation already addresses this?

What is the smallest experiment that distinguishes competing explanations?

Do NOT spend hours doing general research about "running Windows games on Mac."

We already know the target is possible.

Research the specific implementation problem in front of you.

Prefer primary sources:

source code

upstream Wine

DXVK

MoltenVK

VKD3D

Chromium/CEF documentation when relevant

Apple developer documentation

Valve documentation

authoritative issue trackers / patches / commits

Search broadly only after local evidence tells you what to search for.

FIRST HARD GATE: VISIBLE SOURCE-ONLY STEAM

The previous source runtime progressed far enough to start Steam but encountered a black/incorrectly rendered Steam interface.

Treat this as the first major engineering target.

Do NOT jump ahead to polishing the Secunda UI.

Do NOT declare victory because:

wine --version works

a prefix initializes

Steam.exe creates a process

a D3D11 sample creates a device

Steam exists in the process table

Skyrim's process starts

The first gate passes only when the SOURCE-ONLY runtime produces a visibly usable Steam interface.

Instrument it aggressively.

Determine exactly why the Steam/CEF compositor becomes black.

Use:

Wine logs

DXVK logs

Vulkan/MoltenVK diagnostics

CEF/Chromium flags where useful

process trees

loaded-library inspection

API/backend toggles

minimal graphics tests

controlled Wine registry differences

renderer/compositor flags

GPU-process behavior

synchronization experiments

binary/source tracing

comparison against known-good behavior

Change one important variable at a time where practical.

Keep evidence.

SECOND GATE: SKYRIM VERTICAL SLICE

After visible Steam works, move directly into the game.

Acceptance sequence:

Source-only Secunda starts.

Isolated Secunda prefix starts Windows Steam.

Steam UI is visibly usable.

Existing legitimate Skyrim files are detected or made available without damaging the original install.

Steam launches Skyrim Special Edition.

Skyrim launcher/game window renders correctly.

Skyrim main menu renders.

Main-menu audio works.

Keyboard and mouse work.

Enter actual 3D gameplay.

Confirm geometry/materials/lighting are plausibly correct.

Confirm sustained rendering rather than only one frame.

Create or load a save.

Quit cleanly.

Relaunch.

Load the save successfully.

A process merely existing is not acceptance.

Observable behavior is acceptance.

THIRD GATE: PERFORMANCE / STABILITY

Once gameplay works:

Measure rather than guess.

Capture at minimum:

startup behavior

crashes

major graphical corruption

major audio faults

memory growth

obvious stutter/pathological frame pacing

shader compilation behavior

repeated launch reliability

Do not prematurely optimize before correctness.

But do not accept a technically rendering build that is unusably slow if another tractable architecture is available.

FOURTH GATE: SELF-CONTAINED FREE DISTRIBUTION

Only after the runtime works:

Engineer Secunda into something we can actually give another Apple-Silicon Mac user.

Target:

Secunda DMG→ install Secunda→ bootstrap/create source runtime→ Steam login by the user→ install/detect Skyrim→ Play

Determine the most appropriate legal packaging strategy for each dependency.

Include:

source/build provenance

licenses

notices

required source availability/source offer where applicable

reproducible build scripts where practical

dependency versions

checksums

runtime integrity checks

clean uninstall boundaries

Do NOT ship:

user's Steam credentials

Steam session tokens

saves

game files

proprietary CrossOver payload

proprietary Apple payload that cannot legally be redistributed

Separate "free/open-source runtime" from "Apple Developer signing/notarization," which is a distribution-signing concern rather than a paid compatibility-runtime dependency.

FIRST-PRINCIPLES DEBUGGING POLICY

When something fails:

Reproduce the failure.

Capture evidence.

Shrink the problem.

Identify the boundary at which expected behavior diverges.

Form competing hypotheses.

Design the cheapest experiment that distinguishes them.

Run it.

Patch or reconfigure based on evidence.

Retest.

Continue.

Examples:

"Steam window is black" is NOT a blocker.

"DXVK doesn't work" is NOT a blocker.

"MoltenVK emitted an error" is NOT a blocker.

"Wine crashed" is NOT a blocker.

"Compilation failed" is NOT a blocker.

"A patch failed" is NOT a blocker.

"CEF GPU process crashed" is NOT a blocker.

Those are debugging inputs.

Do not confuse "the obvious method failed" with "the objective is impossible."

CAPITAL-B BLOCKER DEFINITION

A BLOCKER is exceptional.

Do not label something a BLOCKER merely because you are stuck.

Before declaring a BLOCKER, you should normally have:

a reproducible failure

relevant logs/traces

source inspection

multiple materially different attempted hypotheses or implementation paths

a narrowed technical boundary

no remaining high-information experiment that can be performed with available access

A legitimate BLOCKER might be:

required source is genuinely unavailable and cannot legally be substituted

an indispensable redistributable component has licensing terms incompatible with the product requirement

required credentials/hardware/user interaction are unavailable

an OS capability is demonstrably inaccessible to unsigned/non-entitled third-party software and no lawful alternative architecture exists

exhaustive evidence shows all viable implementations require something outside our allowed boundary

Even then, do NOT stop at:

"Blocked."

Produce:

exact blocker

evidence

approaches attempted

assumptions falsified

remaining theoretical approaches

what external input would unblock us

SUBAGENT POLICY

Use subagents intelligently, not ceremonially.

Normal parallelism

Subagents are encouraged for INDEPENDENT implementation/research work when parallel execution actually saves time.

Good examples:

Agent A traces Steam/CEF rendering path.

Agent B inspects DXVK/MoltenVK behavior and relevant upstream patches.

Agent C builds a minimal reproducer/instrumentation harness.

Or later:

Agent A handles packaging/licenses/SBOM.

Agent B hardens clean-prefix setup.

Agent C develops fresh-machine acceptance automation.

Give each subagent:

one clear scope

specific files/systems it owns

required evidence/output

explicit instruction not to duplicate the other agents

Wait for independent results when their conclusions influence the same implementation decision.

The MAIN agent owns integration and final architectural decisions.

Do not spawn agents merely to have more opinions.

Reviewer / "what should we do?" agents

These are DIFFERENT.

Do NOT ask reviewer subagents for generic next-step advice during normal debugging.

The primary implementation agent should reason and keep moving.

Only invoke feedback/reviewer subagents when we have reached a genuine CAPITAL-B BLOCKER under the definition above.

At that point, spawn at most 2 focused reviewers in parallel:

Blocker Reviewer A — adversarial debugger

Give it the complete evidence package.

Ask it to:

challenge our blocker conclusion

identify assumptions we accidentally treated as facts

propose experiments we failed to run

find plausible alternate architectures

rank next actions by information gain

Blocker Reviewer B — source/upstream specialist

Give it the same evidence.

Ask it to:

search relevant upstream implementations/issues/commits

identify missing runtime pieces or substitutes

determine whether the blocker is fundamental or merely our implementation

return concrete source references and testable recommendations

Then the primary agent reviews those recommendations and resumes implementation if ANY defensible experiment remains.

Do not use review subagents as permission to quit.

PARALLEL IMPLEMENTATION RULES

Parallelize only separable work.

Avoid having multiple agents edit the same files simultaneously.

Prefer ownership boundaries.

Example:

Agent 1:Steam/CEF diagnostics and reproduction.

Agent 2:Wine graphics backend / DXVK / MoltenVK investigation.

Agent 3:Loaded-library provenance checker proving no CrossOver binary contamination.

Each should return:

findings

exact evidence

files changed if any

commands/tests run

result

recommended integration step

The main agent integrates.

SOURCE-ONLY CONTAMINATION TEST

Create an automated check early.

It should fail the build/test if the source-only acceptance path loads or references forbidden proprietary CrossOver runtime locations.

Inspect:

executable paths

dylib dependencies

child processes

relevant environment variables

Wine runtime path

graphics libraries

Prefer an explicit SOURCE_ONLY=1 or equivalent development mode in which proprietary runtime discovery is disabled entirely.

The source-only branch should make accidental fallback to CrossOver difficult or impossible.

DURABLE PROJECT MEMORY

Long-running work must survive context compaction.

Create or maintain a small set of durable files, for example:

docs/source-only/SPEC.md

objective

non-goals

constraints

acceptance gates

docs/source-only/PLAN.md

current milestone

next experiments

validations

completed milestones

docs/source-only/STATUS.md

latest known-good state

observed failures

decisions and evidence

commands needed to reproduce

current next action

Do not turn these into essays.

They are external working memory.

Update them after meaningful milestones/decisions, not after every command.

GIT POLICY

Work only on source-only-secunda.

Commit validated milestones.

Prefer commits such as:

Fence source-only runtime from CrossOver

Add Steam CEF rendering diagnostics

Fix source runtime Steam compositor

Launch Skyrim through source runtime

Fix source-only Skyrim audio

Bundle redistributable source runtime

Do not commit:

Steam credentials

game binaries if not legally appropriate

saves

giant transient logs

proprietary CrossOver application files

generated prefixes/bottles

caches

Keep the working tree understandable.

COMMUNICATION POLICY

Keep progress updates understandable to someone unfamiliar with Wine internals.

For significant updates explain:

WHAT is being tested/changed

WHY it matters to the final free Secunda product

WHAT the evidence showed

WHAT implementation step follows

Do not narrate every shell command.

Do not stop implementation just to write frequent status messages.

Do not repeatedly ask the user "should I continue?"

Continue while a valid engineering path exists.

Only request user interaction when genuinely necessary, for example:

Steam login

observing actual speaker audio if inaccessible programmatically

protected macOS permission

credential/signing requirement

Never request Steam passwords or attempt to capture them.

DECISION PRIORITY

When choosing between:

A. writing more about the problem

and

B. building an experiment that teaches us something,

choose B.

When choosing between:

A. a giant rewrite

and

B. a minimal experiment that proves the suspected boundary,

usually choose B first.

When choosing between:

A. declaring a technology incompatible

and

B. inspecting why the actual machine rejected it,

choose B.

When choosing between:

A. polishing launcher UI

and

B. making source-only Steam/Skyrim actually function,

choose B.

END CONDITION

Do not call this project finished until the acceptance evidence demonstrates:

SOURCE-ONLY Secunda+no proprietary CrossOver runtime usage+visible Steam+Skyrim graphics+Skyrim audio+input+actual gameplay+save+quit+relaunch+load+shareable free-runtime packaging path

If all of those pass, produce a concise final engineering report containing:

architecture

exact runtime components/versions

patches carried

build commands

acceptance evidence

remaining known limitations

redistribution/license obligations

clean-machine setup procedure

Until then:

KEEP IMPLEMENTING.