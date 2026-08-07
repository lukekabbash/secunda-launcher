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
        let paths = SecundaPaths(applicationSupport: root, repositoryRoot: nil)
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
            PrimaryAction.locateRuntime.title == "Restore Secunda Engine",
            "source runtime recovery action",
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
                "CX_BOTTLE_PATH": "/tmp/external",
                "DYLD_LIBRARY_PATH": "/Applications/CrossOver.app/Contents/Libraries",
                "PATH": "/usr/bin:/bin"
            ],
            overrides: [
                "WINEPREFIX": paths.bottleRoot.path,
                "PATH": "/tmp/secunda/bin:/usr/bin:/bin",
                "CX_ROOT": "/tmp/external",
                "WINEDLLPATH": "/Applications/CrossOver.app/Contents/Libraries"
            ]
        )
        expect(sanitized["CX_BOTTLE_PATH"] == nil, "foreign bottle environment removal", passes: &passes, failures: &failures)
        expect(sanitized["DYLD_LIBRARY_PATH"] == nil, "inherited library path removal", passes: &passes, failures: &failures)
        expect(sanitized["WINEDLLPATH"] == nil, "forbidden override rejection", passes: &passes, failures: &failures)
        expect(sanitized["CX_ROOT"] == nil, "foreign runtime override removal", passes: &passes, failures: &failures)
        expect(sanitized["WINEPREFIX"] == paths.bottleRoot.path, "managed prefix override", passes: &passes, failures: &failures)
        expect(
            sanitized["PATH"] == "/tmp/secunda/bin:/usr/bin:/bin",
            "managed executable path",
            passes: &passes,
            failures: &failures
        )

        let settings = LauncherSettings()
        expect(!settings.launchInWindow, "display defaults", passes: &passes, failures: &failures)
        expect(!settings.enableDiagnostics, "diagnostic defaults", passes: &passes, failures: &failures)
        expect(settings.width == 1920 && settings.height == 1080, "resolution defaults", passes: &passes, failures: &failures)

        let setupProgress = SetupProgress(
            step: 2,
            totalSteps: 4,
            title: "Installing",
            detail: "Test"
        )
        expect(setupProgress.fraction == 0.5, "setup progress fraction", passes: &passes, failures: &failures)
        expect(setupProgress.stepLabel == "Step 2 of 4", "setup progress label", passes: &passes, failures: &failures)

        let profile = GameProfileWriter.updatingDisplaySection(
            in: "[Display]\r\nbFull Screen=0\r\n[Audio]\r\nfMusicDuckingSeconds=6.0\r\n",
            settings: settings
        )
        expect(profile.contains("bFull Screen=1"), "fullscreen profile", passes: &passes, failures: &failures)
        expect(profile.contains("iSize W=1920"), "profile width", passes: &passes, failures: &failures)
        expect(profile.contains("[Audio]"), "profile preservation", passes: &passes, failures: &failures)

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
