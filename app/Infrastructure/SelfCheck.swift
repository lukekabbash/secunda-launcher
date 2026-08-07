import Foundation

enum SelfCheck {
    static func run() -> Int32 {
        var failures: [String] = []
        var passes = 0

        let override = SecundaPaths.discoverRepositoryRoot(
            environment: ["SECUNDA_REPOSITORY_ROOT": "/tmp/secunda-source"],
            currentDirectory: URL(fileURLWithPath: "/")
        )
        expect(override?.path == "/tmp/secunda-source", "repository override", passes: &passes, failures: &failures)

        let root = URL(fileURLWithPath: "/tmp/secunda-self-check", isDirectory: true)
        let paths = SecundaPaths(applicationSupport: root, repositoryRoot: nil, environment: [:])
        expect(
            paths.bottleRoot.path.hasPrefix(paths.applicationSupport.path),
            "bottle path containment",
            passes: &passes,
            failures: &failures
        )
        expect(
            paths.logsDirectory.path.hasPrefix(paths.applicationSupport.path),
            "log path containment",
            passes: &passes,
            failures: &failures
        )
        expect(
            paths.backupsDirectory.path.hasPrefix(paths.applicationSupport.path),
            "backup path containment",
            passes: &passes,
            failures: &failures
        )
        expect(
            paths.graphicsCacheDirectory.path.hasPrefix(paths.applicationSupport.path),
            "graphics cache containment",
            passes: &passes,
            failures: &failures
        )
        expect(
            paths.activeWindowsUserDirectory().lastPathComponent == "secunda",
            "managed Windows user fallback",
            passes: &passes,
            failures: &failures
        )
        expect(SkyrimService.steamAppID == "489830", "Steam app identifier", passes: &passes, failures: &failures)
        expect(
            PrimaryAction.locateRuntime.title == "Open Setup Help",
            "truthful source runtime recovery action",
            passes: &passes,
            failures: &failures
        )
        expect(
            SteamService.compatibilityArguments.contains("-system-composer")
                && SteamService.compatibilityArguments.contains("-cef-allow-browser-underlays")
                && SteamService.compatibilityArguments.contains("-no-cef-sandbox"),
            "Steam UI compatibility arguments",
            passes: &passes,
            failures: &failures
        )
        let sourceRuntime = RuntimeDescriptor(
            wineExecutable: URL(fileURLWithPath: "/tmp/secunda/wine"),
            version: "11.0",
            origin: .sourceBuild,
            bottleRoot: paths.bottleRoot
        )
        expect(
            sourceRuntime.wineArguments(for: ["reg", "query"]) == ["reg", "query"],
            "source runtime command arguments",
            passes: &passes,
            failures: &failures
        )
        let runtimeEnvironment = RuntimeManager(
            paths: paths,
            processRunner: ProcessRunner()
        ).environment(for: sourceRuntime, diagnostics: false)
        expect(
            runtimeEnvironment["SECUNDA_CEF_IN_PROCESS_GPU"] == "1",
            "embedded browser compositor mode",
            passes: &passes,
            failures: &failures
        )
        expect(
            runtimeEnvironment["WINEMSYNC"] == "1" && runtimeEnvironment["WINEESYNC"] == nil,
            "Apple synchronization mode",
            passes: &passes,
            failures: &failures
        )
        let bundledRuntime = RuntimeDescriptor(
            wineExecutable: URL(fileURLWithPath: "/tmp/secunda-bundled/bin/wine"),
            version: "11.0",
            origin: .bundled,
            bottleRoot: paths.bottleRoot
        )
        let bundledEnvironment = RuntimeManager(
            paths: paths,
            processRunner: ProcessRunner()
        ).environment(for: bundledRuntime, diagnostics: false)
        expect(
            runtimeEnvironment["DYLD_LIBRARY_PATH"] != nil
                && bundledEnvironment["DYLD_LIBRARY_PATH"] == nil,
            "packaged runtime avoids DYLD environment dependency",
            passes: &passes,
            failures: &failures
        )
        expect(
            SourceRuntimePolicy.containsForbiddenReference(
                "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"
            ),
            "forbidden application path",
            passes: &passes,
            failures: &failures
        )
        expect(
            SourceRuntimePolicy.containsForbiddenReference("/runtime/lib64/apple_gptk/d3d11.dll"),
            "forbidden graphics payload path",
            passes: &passes,
            failures: &failures
        )
        expect(
            SourceRuntimePolicy.containsForbiddenReference("/runtime/lib/libd3dshared.dylib"),
            "forbidden shared graphics library",
            passes: &passes,
            failures: &failures
        )

        let runtimeFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("secunda-policy-\(UUID().uuidString)", isDirectory: true)
        let fixtureExecutable = runtimeFixture.appendingPathComponent("bin/wine")
        let fixtureManifest = runtimeFixture.appendingPathComponent(
            SourceRuntimePolicy.provenanceRelativePath
        )
        try? FileManager.default.createDirectory(
            at: fixtureManifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let validManifest = """
        {
          "formatVersion": 1,
          "runtimeKind": "secunda-source-runtime",
          "architecture": "x86_64",
          "components": [
            {"name": "Wine", "version": "11.0"},
            {"name": "DXMT", "version": "0.80"}
          ]
        }
        """
        try? Data(validManifest.utf8).write(to: fixtureManifest, options: .atomic)
        expect(
            SourceRuntimePolicy.allows(
                executable: fixtureExecutable,
                trustedRuntimeRoot: runtimeFixture
            ),
            "valid source runtime provenance",
            passes: &passes,
            failures: &failures
        )
        expect(
            !SourceRuntimePolicy.allows(
                executable: fixtureExecutable,
                trustedRuntimeRoot: runtimeFixture.deletingLastPathComponent()
                    .appendingPathComponent("different-runtime")
            ),
            "runtime root containment",
            passes: &passes,
            failures: &failures
        )
        try? Data("{}".utf8).write(to: fixtureManifest, options: .atomic)
        expect(
            !SourceRuntimePolicy.allows(
                executable: fixtureExecutable,
                trustedRuntimeRoot: runtimeFixture
            ),
            "malformed source runtime provenance",
            passes: &passes,
            failures: &failures
        )
        try? FileManager.default.removeItem(at: runtimeFixture)

        let sanitized = SourceRuntimePolicy.sanitizedEnvironment(
            base: [
                "AUTH_TOKEN": "must-not-reach-wine",
                "CX_BOTTLE_PATH": "/tmp/external",
                "DYLD_LIBRARY_PATH": "/Applications/CrossOver.app/Contents/Libraries",
                "HOME": "/Users/tester",
                "LANG": "en_US.UTF-8",
                "PATH": "/usr/bin:/bin",
                "SSH_AUTH_SOCK": "/tmp/agent.sock",
                "STEAM_PASSWORD": "must-not-reach-wine",
                "SteamLogin": "must-not-reach-wine",
                "TMPDIR": "/tmp/secunda"
            ],
            overrides: [
                "WINEPREFIX": paths.bottleRoot.path,
                "PATH": "/tmp/secunda/bin:/usr/bin:/bin",
                "SteamAppId": SkyrimService.steamAppID,
                "SteamGameId": SkyrimService.steamAppID,
                "CX_ROOT": "/tmp/external",
                "WINEDLLPATH": "/Applications/CrossOver.app/Contents/Libraries"
            ]
        )
        expect(sanitized["CX_BOTTLE_PATH"] == nil, "foreign bottle environment removal", passes: &passes, failures: &failures)
        expect(sanitized["DYLD_LIBRARY_PATH"] == nil, "inherited library path removal", passes: &passes, failures: &failures)
        expect(sanitized["WINEDLLPATH"] == nil, "forbidden override rejection", passes: &passes, failures: &failures)
        expect(sanitized["CX_ROOT"] == nil, "foreign runtime override removal", passes: &passes, failures: &failures)
        expect(sanitized["AUTH_TOKEN"] == nil, "parent secret removal", passes: &passes, failures: &failures)
        expect(sanitized["SSH_AUTH_SOCK"] == nil, "parent credential socket removal", passes: &passes, failures: &failures)
        expect(
            sanitized["STEAM_PASSWORD"] == nil && sanitized["SteamLogin"] == nil,
            "Steam credential environment removal",
            passes: &passes,
            failures: &failures
        )
        expect(
            sanitized["SteamAppId"] == SkyrimService.steamAppID
                && sanitized["SteamGameId"] == SkyrimService.steamAppID,
            "public Steam game identifiers",
            passes: &passes,
            failures: &failures
        )
        expect(
            sanitized["HOME"] == "/Users/tester"
                && sanitized["LANG"] == "en_US.UTF-8"
                && sanitized["TMPDIR"] == "/tmp/secunda",
            "required host environment preservation",
            passes: &passes,
            failures: &failures
        )
        expect(sanitized["WINEPREFIX"] == paths.bottleRoot.path, "managed prefix override", passes: &passes, failures: &failures)
        expect(
            sanitized["PATH"] == "/tmp/secunda/bin:/usr/bin:/bin",
            "managed executable path",
            passes: &passes,
            failures: &failures
        )

        let settings = LauncherSettings()
        expect(settings.displayMode == .borderlessFullscreen, "display defaults", passes: &passes, failures: &failures)
        expect(settings.verticalSync, "vsync defaults", passes: &passes, failures: &failures)
        expect(settings.fieldOfView == 95, "field of view default", passes: &passes, failures: &failures)
        expect(!settings.enableDiagnostics, "diagnostic defaults", passes: &passes, failures: &failures)
        expect(settings.width == 1920 && settings.height == 1080, "resolution defaults", passes: &passes, failures: &failures)

        let setupProgress = SetupProgress(
            step: 2,
            totalSteps: 4,
            title: "Installing",
            detail: "Test"
        )
        expect(setupProgress.fraction == 0.25, "truthful in-progress fraction", passes: &passes, failures: &failures)
        expect(setupProgress.stepLabel == "Step 2 of 4", "setup progress label", passes: &passes, failures: &failures)

        let handoffChecks = LauncherHandoffSelfCheck.run(root: root, paths: paths)
        passes += handoffChecks.passes
        failures.append(contentsOf: handoffChecks.failures)

        expect(
            ProcessRunnerSelfCheck.captureCompletesWhenChildInheritsOutput(),
            "bounded process capture ignores inherited output handles",
            passes: &passes,
            failures: &failures
        )
        expect(
            ProcessRunnerSelfCheck.capturePreservesMultipleChunksInOrder(),
            "bounded process capture preserves multi-chunk output order",
            passes: &passes,
            failures: &failures
        )

        let profile = GameProfileWriter.updatingDisplaySection(
            in: "[Display]\r\nbFull Screen=1\r\n[Audio]\r\nfMusicDuckingSeconds=6.0\r\n",
            settings: settings
        )
        expect(profile.contains("bFull Screen=0"), "borderless profile disables exclusive fullscreen", passes: &passes, failures: &failures)
        expect(profile.contains("bBorderless=1"), "borderless profile", passes: &passes, failures: &failures)
        expect(profile.contains("iVSyncPresentInterval=1"), "vsync profile", passes: &passes, failures: &failures)
        expect(profile.contains("iSize W=1920"), "profile width", passes: &passes, failures: &failures)
        expect(profile.contains("[Audio]"), "profile preservation", passes: &passes, failures: &failures)

        var exclusiveSettings = LauncherSettings()
        exclusiveSettings.displayMode = .exclusiveFullscreen
        let exclusiveProfile = GameProfileWriter.updatingDisplaySection(
            in: "[Display]\r\n",
            settings: exclusiveSettings
        )
        expect(exclusiveProfile.contains("bFull Screen=1"), "exclusive fullscreen profile", passes: &passes, failures: &failures)
        expect(exclusiveProfile.contains("bBorderless=0"), "exclusive borderless off", passes: &passes, failures: &failures)

        let customProfile = GameProfileWriter.updatingCustomDisplaySection(
            in: "[General]\r\nsLanguage=ENGLISH\r\n",
            settings: settings
        )
        expect(customProfile.contains("fDefaultWorldFOV=95"), "world FOV profile", passes: &passes, failures: &failures)
        expect(customProfile.contains("fDefault1stPersonFOV=95"), "first-person FOV profile", passes: &passes, failures: &failures)
        expect(customProfile.contains("sLanguage=ENGLISH"), "custom ini preservation", passes: &passes, failures: &failures)

        let legacySettings = try? JSONDecoder().decode(
            LauncherSettings.self,
            from: Data(#"{"launchInWindow":true,"width":1280,"height":800,"enableDiagnostics":false}"#.utf8)
        )
        expect(legacySettings?.displayMode == .windowed, "legacy windowed migration", passes: &passes, failures: &failures)
        expect(legacySettings?.verticalSync == true, "legacy vsync default", passes: &passes, failures: &failures)

        if failures.isEmpty {
            print("Secunda self-check: \(passes) contracts passed")
            return 0
        }

        for failure in failures {
            print("FAILED: \(failure)")
        }
        return 1
    }

    private static func expect(
        _ condition: Bool,
        _ name: String,
        passes: inout Int,
        failures: inout [String]
    ) {
        if condition {
            passes += 1
        } else {
            failures.append(name)
        }
    }
}
