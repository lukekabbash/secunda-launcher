# Secunda Launcher product specification

## Purpose

Secunda makes a separately owned Windows Steam copy of Skyrim Special Edition feel dependable on Apple-silicon Macs. It is an unofficial narrow launcher, not a general Windows environment or game library.

## Product boundary

Secunda owns one redistributable source-built Wine/DXMT runtime, one isolated prefix, its runtime configuration, local backups, caches, and diagnostic logs. It never discovers or depends on a proprietary compatibility application.

Steam owns authentication, entitlement, download, verification, updates, and cloud sync. Steam and Skyrim binaries, another player's session, game content, saves, and diagnostics are never embedded in the app or DMG.

The compatibility path is:

```text
Secunda.app -> source-built x86-64 Wine/DXMT -> Rosetta -> private Windows prefix -> Steam -> Skyrim -> macOS Metal/CoreAudio
```

## Primary experience

1. Confirm the Apple-silicon Mac, Rosetta, bundled runtime, and free disk space are ready.
2. Create one private managed 64-bit prefix.
3. Apply the tested display, graphics, synchronization, and audio profile.
4. Download the Windows Steam installer directly from Valve.
5. Open Steam's own visible login UI for the player to authenticate.
6. Let Steam install or detect Skyrim Special Edition.
7. Launch Skyrim through Steam, then keep saves and recovery evidence within Secunda's managed boundary.

## Quality bar

- One dominant, truthful action at every setup stage.
- Persistent progress for long downloads/installs and staged progress for launch handoffs.
- Original moonlit visual language with no copied game assets or marks.
- No credential capture or launcher-managed authentication.
- Managed writes remain beneath `~/Library/Application Support/Secunda Launcher`.
- Destructive recovery actions name and validate their exact target.
- Gameplay acceptance covers visible Steam, rendering, audio, keyboard/mouse input, actual gameplay, save, clean quit, relaunch, and load.
- Performance claims are measured with frame cadence, shader, resource, and repeat-launch evidence.

## Explicit non-goals for the first release

- Generic Windows application installation.
- Mod-manager or script-extender support.
- A multi-game library.
- Bundling Steam, Skyrim, a Steam session, or user saves.
- Requiring or redistributing a proprietary compatibility application.
- App Store distribution.
