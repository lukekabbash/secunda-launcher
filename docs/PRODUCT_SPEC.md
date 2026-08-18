# Secunda Launcher product specification

## Purpose

Secunda makes a curated library of separately owned Windows Steam games approachable on Apple-silicon Macs. It is an unofficial, profile-driven launcher, not a general Windows environment or arbitrary application runner.

## Product boundary

Secunda owns one redistributable source-built Wine runtime with packaged graphics translation, one isolated prefix, its profile configuration, local backups, caches, and diagnostic logs. It never discovers or depends on a proprietary compatibility application.

Steam owns authentication, entitlement, download, verification, updates, and cloud sync. Steam binaries, supported-game binaries and content, another player's session, saves, and diagnostics are never embedded in the app or DMG.

The compatibility path is:

```text
Secunda.app -> source-built Wine runtime -> Rosetta -> private Windows prefix -> Steam -> selected profile -> macOS graphics/audio
```

## Supported library and evidence

The library currently profiles Skyrim Special Edition, Enderal: Forgotten Stories (Special Edition), Fallout 4, Fallout: New Vegas, Supreme Commander, Supreme Commander: Forged Alliance, Supreme Commander 2, STAR WARS Battlefront II (Classic, 2005), Insurgency, Portal 2, Half-Life 2, Angels Fall First, and the Campaign, Multiplayer, and Zombies components of Call of Duty: Black Ops II.

Skyrim Special Edition is the proven vertical slice. Fallout 4, Supreme Commander 2, and Insurgency are played on a 2026 MacBook Air M5. The remaining titles, including Enderal, New Vegas, Portal 2, Half-Life 2, and Black Ops II, are experimental catalog profiles. Catalog support must never be presented as proof of rendered gameplay or working multiplayer.

## Primary experience

1. Confirm the Apple-silicon Mac, Rosetta, bundled runtime, and free disk space are ready.
2. Create one private managed 64-bit prefix.
3. Apply the tested display, graphics, synchronization, and audio profile.
4. Download the Windows Steam installer directly from Valve.
5. Open Steam's own visible login UI for the player to authenticate.
6. Let Steam install or detect a supported, separately owned game.
7. Select its Secunda profile and launch through Steam, then keep saves and recovery evidence within Secunda's managed boundary.

## Quality bar

- One dominant, truthful action at every setup stage.
- Persistent progress for long downloads/installs and staged progress for launch handoffs.
- Original moonlit visual language with no copied game assets or marks.
- No credential capture or launcher-managed authentication.
- Managed writes remain beneath `~/Library/Application Support/Secunda Launcher`.
- Destructive recovery actions name and validate their exact target.
- Gameplay acceptance is recorded per profile and covers visible Steam, rendering, audio, keyboard/mouse input, actual gameplay, save where supported, clean quit, relaunch, and load.
- Performance claims are measured with frame cadence, shader, resource, and repeat-launch evidence.

## Explicit non-goals for the first release

- Generic Windows application installation.
- Automatic support or compatibility claims for unlisted games.
- Mod-manager or script-extender support.
- Bundling Steam, any game, a Steam session, or user saves.
- Requiring or redistributing a proprietary compatibility application.
- App Store distribution.
