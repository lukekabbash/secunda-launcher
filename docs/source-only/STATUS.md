# Source-only status

Updated: 2026-08-07

## Latest known-good state

- Branch: `source-only-secunda`; `main` remains at `ad1ef70`.
- Source runtime: x86-64 Wine 11.0 under Rosetta with DXMT 0.80, located at `Runtime/wine`.
- Acceptance prefix: an APFS clone named `SkyrimSE-SourceClone`; its Documents and saves are private copies, not host symlinks.
- The launcher no longer contains runtime discovery or bottle paths for the proprietary baseline.
- Parent loader variables are scrubbed before every child launch.
- Runtime discovery requires a parsed source-runtime provenance manifest.
- Gate 1 passed: source-only Steam rendered visibly, authenticated from cached session state, and completed three repeat connections.
- Gate 2 automated acceptance reached the launcher, main menu, sustained Riverwood gameplay, keyboard input, a clone-only quicksave, exit-code-0 quit, relaunch, and successful load of the refreshed save.
- Live Skyrim, Steam, Wine server, and mapped-library provenance passed with no forbidden runtime contamination.
- Skyrim registered active CoreAudio output for 33 of 33 samples and loaded the complete source Wine audio chain. The default speakers were muted, so an unmuted quality check or pre-mute PCM probe remains.
- Ten loaded-gameplay samples averaged 805.1 MiB RSS with a 0.6 MiB range; Skyrim averaged 217.5% CPU, Steam 2.0%, and Wine server 4.8%.
- The expanded Swift, contamination, audio, and observability checks are being consolidated before the next milestone commit.

## Accepted runtime fixes

- Steam CEF runs its GPU work in-process for the top-level helper, avoiding DXMT 0.80's rejected cross-process window swapchain.
- Wine's upstream Clang syscall-ABI wrappers were backported to the supplied Wine 11.0 layout. This fixed Steam's machine-ID directory enumeration and ended the `Schedule init returned 22` login loop.
- `WINEMSYNC=1` is used for the supplied msync implementation.
- Child processes receive a safe host-variable allowlist instead of inheriting developer credentials or unrelated loader state.
- XAudio and X3DAudio use Wine's built-in implementations in the source-only prefix.

## Current caveats

- One first-run synthetic `E`-key experiment inside the journal ended with `0xC0000005`. Two later runs loaded the quicksave and exited through `WM_CLOSE` with code 0; retain the abnormal run as stability evidence.
- The speaker endpoint was muted at volume zero during unattended audio acceptance. Do not claim audible quality until a pre-mute PCM tap or human listening check passes.
- The staged runtime still needs a clean macOS-15 rebuild before fresh-machine distribution: existing binaries retain build RPATHs and a macOS 26 minimum version.

## Next action

1. Attempt a no-install pre-mute PCM process tap without changing speaker state.
2. Run a longer stability/resource sample and repeat-launch loop against the source-only runtime.
3. Finish the relocatable, stripped, integrity-sealed runtime and audited DMG.
4. Re-run visible Steam and the complete Skyrim slice from the packaged app on a clean Apple-Silicon Mac.
