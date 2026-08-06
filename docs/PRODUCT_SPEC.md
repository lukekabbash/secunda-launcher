# Secunda Launcher product specification

## Purpose

Secunda Launcher makes one legally owned Steam copy of Skyrim Special Edition feel native and dependable on Apple-silicon Macs. It is an unofficial launcher and compatibility wrapper, not a general Windows environment.

## Product boundary

Secunda owns one isolated bottle, its runtime configuration, local backups, and diagnostic logs. It may coordinate with a separately installed compatibility engine but never copies or redistributes that engine. Steam owns authentication, entitlement, download, verification, and cloud sync. Bethesda and Valve game/client files are never bundled or redistributed.

## Primary experience

1. Confirm the Mac and runtime are ready.
2. Create one managed 64-bit bottle.
3. Download the Windows Steam installer directly from Valve.
4. Open Steam for the player to authenticate.
5. Detect Skyrim Special Edition after Steam installs it.
6. Launch Skyrim through Steam.
7. Protect saves and expose actionable recovery evidence.

## Quality bar

- One dominant action at every stage.
- Original moonlit visual language with no copied game assets or marks.
- No credential capture or launcher-managed authentication.
- Managed writes remain beneath Secunda's application-support directory.
- Destructive recovery actions must name and validate their exact target.
- Gameplay acceptance covers the Helgen sequence, audio, rendering, input, save, quit, and reload.

## Explicit non-goals for the first testable release

- Generic Windows application installation.
- Mod-manager or script-extender support.
- A multi-game library.
- Bundling Steam, Skyrim, or a Steam session.
- App Store distribution.
