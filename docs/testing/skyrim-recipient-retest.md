# Skyrim recipient retest

This procedure is for the instrumented `Secunda Launcher (Skyrim Diagnostic)` artifact produced by PR #10. It uses the packaged compatibility runtime from the public v0.1.4 TEST-ONLY DMG and a patched native launcher.

## Before testing

- Do not delete the existing Secunda game space or saves.
- Do not disable Gatekeeper, SIP, or other macOS security controls.
- Keep the existing Steam/Skyrim installation so this reproduces the recipient failure state instead of replacing it.
- The diagnostic build forces Secunda's existing bounded verbose logging on at load. Leave **Write detailed logs** enabled.

## Verification

1. Open the diagnostic app normally.
2. Confirm Steam is signed in and Skyrim Special Edition is installed.
3. Launch Skyrim once using the settings that previously failed.
4. If the menu appears, enter actual gameplay. Confirm rendered world, dialogue/audio, keyboard/mouse input, and a save/load if convenient. Quit cleanly, relaunch, and confirm it opens again.
5. If the first attempt fails, do not repeatedly reinstall or reset the game space. Preserve that attempt before trying other settings.

A successful process alone is not a pass: Secunda now requires an owned presentable Skyrim window before reporting launch success.

## Evidence if it still fails

Use **Settings → Reveal Logs**. The directory is:

`~/Library/Application Support/Secunda Launcher/Logs`

Preserve files from the failed attempt, especially:

- `launch-records.jsonl` — privacy-safe attempt/request/window timeline.
- `game-launch-skyrim-se.log` — bounded verbose Wine/game launch output; now ends with host process termination status when the directly launched worker exits.
- `steam-launch.log` — verbose Steam handoff output. This is intentionally excluded from the in-app support excerpt because it can contain account/session-adjacent data; share only for this controlled debugging case.
- DXMT logs modified at the same timestamp.
- `voice-audio-install.log` if Secunda repairs the XAudio dependency.
- The generated diagnostics report from Settings.

Also note the visible symptom: Secunda itself closed, Skyrim process vanished, black/no window, Bethesda launcher appeared then disappeared, or a window appeared and crashed later.

The diagnostics report embeds the diagnostic source commit, so a failure can be matched to the exact patched launcher rather than inferred from a generic v0.1.4 label.

## Why this build

Skyrim was previously accepted and explicitly confirmed working on the reference Mac. Comparing that known-good source to v0.1.4 did not reveal a Skyrim launch-profile rewrite. PR #9 fixes a concrete persistent-state defect where malformed native XAudio DLLs could be treated as installed. PR #10 adds real-window launch verification and attempt-linked evidence, while keeping the v0.1.4 packaged compatibility runtime constant.
