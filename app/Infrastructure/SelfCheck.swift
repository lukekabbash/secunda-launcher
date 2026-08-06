import Foundation

enum SelfCheck {
    static func run() -> Int32 {
        var failures: [String] = []

        let override = SecundaPaths.discoverRepositoryRoot(
            environment: ["SECUNDA_REPOSITORY_ROOT": "/tmp/secunda-source"],
            currentDirectory: URL(fileURLWithPath: "/")
        )
        expect(override?.path == "/tmp/secunda-source", "repository override", failures: &failures)

        let root = URL(fileURLWithPath: "/tmp/secunda-self-check", isDirectory: true)
        let paths = SecundaPaths(applicationSupport: root, repositoryRoot: nil)
        expect(
            paths.bottleRoot.path.hasPrefix(paths.applicationSupport.path),
            "bottle path containment",
            failures: &failures
        )
        expect(
            paths.crossOverBottleRoot.path.hasPrefix(paths.applicationSupport.path),
            "CrossOver bottle path containment",
            failures: &failures
        )
        expect(
            paths.crossOverBottleRoot != paths.bottleRoot,
            "isolated engine bottles",
            failures: &failures
        )
        expect(
            paths.logsDirectory.path.hasPrefix(paths.applicationSupport.path),
            "log path containment",
            failures: &failures
        )
        expect(
            paths.backupsDirectory.path.hasPrefix(paths.applicationSupport.path),
            "backup path containment",
            failures: &failures
        )
        expect(
            paths.graphicsCacheDirectory.path.hasPrefix(paths.applicationSupport.path),
            "graphics cache containment",
            failures: &failures
        )
        expect(
            paths.activeWindowsUserDirectory().lastPathComponent == "crossover",
            "managed Windows user fallback",
            failures: &failures
        )
        expect(SkyrimService.steamAppID == "489830", "Steam app identifier", failures: &failures)
        expect(
            SteamService.compatibilityArguments.contains("-system-composer")
                && SteamService.compatibilityArguments.contains("-cef-allow-browser-underlays")
                && SteamService.compatibilityArguments.contains("-no-cef-sandbox"),
            "Steam UI software rendering",
            failures: &failures
        )

        let crossOverRuntime = RuntimeDescriptor(
            wineExecutable: URL(fileURLWithPath: "/tmp/crossover/wine"),
            version: "26.3",
            origin: .crossOver,
            engine: .crossOver,
            bottleRoot: paths.crossOverBottleRoot,
            bottleContainer: paths.bottlesDirectory,
            bottleName: paths.crossOverBottleName,
            bottleExecutable: URL(fileURLWithPath: "/tmp/crossover/cxbottle")
        )
        expect(
            crossOverRuntime.wineArguments(for: ["reg", "query"]) == [
                "--bottle", paths.crossOverBottleName, "reg", "query"
            ],
            "CrossOver bottle command prefix",
            failures: &failures
        )

        let settings = LauncherSettings()
        expect(settings.runtimeExecutablePath == nil, "runtime defaults", failures: &failures)
        expect(!settings.launchInWindow, "display defaults", failures: &failures)
        expect(!settings.enableDiagnostics, "diagnostic defaults", failures: &failures)
        expect(settings.width == 1920 && settings.height == 1080, "resolution defaults", failures: &failures)

        let setupProgress = SetupProgress(
            step: 2,
            totalSteps: 4,
            title: "Installing",
            detail: "Test"
        )
        expect(setupProgress.fraction == 0.5, "setup progress fraction", failures: &failures)
        expect(setupProgress.stepLabel == "Step 2 of 4", "setup progress label", failures: &failures)

        let profile = GameProfileWriter.updatingDisplaySection(
            in: "[Display]\r\nbFull Screen=0\r\n[Audio]\r\nfMusicDuckingSeconds=6.0\r\n",
            settings: settings
        )
        expect(profile.contains("bFull Screen=1"), "fullscreen profile", failures: &failures)
        expect(profile.contains("iSize W=1920"), "profile width", failures: &failures)
        expect(profile.contains("[Audio]"), "profile preservation", failures: &failures)

        if failures.isEmpty {
            print("Secunda self-check: 20 contracts passed")
            return 0
        }

        for failure in failures {
            print("FAILED: \(failure)")
        }
        return 1
    }

    private static func expect(_ condition: Bool, _ name: String, failures: inout [String]) {
        if !condition { failures.append(name) }
    }
}
