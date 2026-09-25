# Launch readiness regression tests

Run `bash scripts/test-launch-readiness.sh` with Swift 6.1 or newer. The script
compiles the production `RuntimeManager`, `VoiceAudioService`, and
`LaunchReadinessPolicy` against deterministic process/path/policy test doubles.
It uses an isolated temporary directory and synthetic PE fixtures, not Wine,
Steam, a network download, real Microsoft DLLs, or a player's existing prefix.
The fake runtime's provenance/integrity policies are test boundaries, not a test
of the real security policies. The existing full-app self-check remains separate.

Coverage includes per-invocation version parsing, timeout/output-limit wiring,
nonzero and failed probes, stale logs, bounded probe metadata, malformed x64 PE
payloads, whole-set audio readiness, validation before any live DLL replacement,
retry/repair, staging paths, and avoiding an unnecessary reinstall.

The audio policy checks structure and architecture. It does **not** authenticate
the publisher, verify a cryptographic payload digest, or guarantee loader success.
Acquisition still uses the existing Microsoft HTTPS redistributable URL. A valid
PE structure must not be presented as proof of Microsoft provenance. Payload
signature/checksum verification remains follow-up work under LUK-254.

Expansion now happens in staging. All three payloads are validated before live
writes; each live DLL is replaced using an atomic file write. This is **not** an
atomic transaction across all three files. An interrupted/failed commit must not
be treated as installation success; the next attempt validates the set again.

## Required macOS/game acceptance before closing the reported crashes

The PR workflow runs the new unit regressions, a native launcher build, and the
existing launcher self-checks on macOS. Those checks do not establish gameplay.
Retest the real Microsoft redistributable extraction and installed payloads,
including a clean test prefix and repair of an invalid audio installation, without
deleting the player's existing games or saves.

For Skyrim, use the exact packaged build on the affected recipient laptop and
record whether the launcher, Wine worker, or game exits. Compare native audio
on/off only as a controlled diagnostic. Verify a rendered menu/game, audio,
input, save/load, clean quit, and relaunch. No claim is made that invalid audio
files caused the reported crash.

Black Ops II campaign's previously documented runtime exit is not patched here.
Keep campaign, multiplayer, and Zombies acceptance distinct. Full attempt-linked
failure capture, support export, and Skyrim window-confirmation work remain in
LUK-252, LUK-253, and LUK-256 respectively. LUK-250 and LUK-251 remain open.
