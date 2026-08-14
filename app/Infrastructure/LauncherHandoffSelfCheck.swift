import Foundation

struct LauncherHandoffCheckSummary {
    var passes = 0
    var failures: [String] = []

    mutating func expect(_ condition: Bool, _ name: String) {
        if condition {
            passes += 1
        } else {
            failures.append(name)
        }
    }
}

enum LauncherHandoffSelfCheck {
    static func run(root: URL, paths: SecundaPaths) -> LauncherHandoffCheckSummary {
        var checks = LauncherHandoffCheckSummary()
        checkDevelopmentOverrides(root: root, checks: &checks)
        checkCompatibilityProfile(checks: &checks)
        checkRuntimeIntegrity(checks: &checks)
        checkHostPreflight(checks: &checks)
        checkSetupJourney(paths: paths, checks: &checks)
        checkLaunchHandoff(checks: &checks)
        checkSteamInstallProbe(checks: &checks)
        checkDocumentsIsolation(checks: &checks)
        checkDiagnosticRedaction(paths: paths, checks: &checks)
        return checks
    }

    private static func checkDevelopmentOverrides(
        root: URL,
        checks: inout LauncherHandoffCheckSummary
    ) {
        let sourceRoot = URL(fileURLWithPath: "/tmp/secunda-source")
        let overridePaths = SecundaPaths(
            applicationSupport: root,
            repositoryRoot: sourceRoot,
            environment: [
                "SECUNDA_BOTTLE_NAME": "SkyrimSE-SourceClone",
                "SECUNDA_DEVELOPER_MODE": "1"
            ]
        )
        checks.expect(
            overridePaths.usesBottleOverride
                && overridePaths.bottleRoot.lastPathComponent == "SkyrimSE-SourceClone"
                && overridePaths.isManagedBottleRoot(overridePaths.bottleRoot),
            "contained development bottle override"
        )

        let rejectedNames = [
            "../SkyrimSE",
            "/tmp/SkyrimSE",
            ".hidden",
            "SkyrimSE-CrossOver",
            "CodeWeavers-Skyrim"
        ]
        checks.expect(
            rejectedNames.allSatisfy { SecundaPaths.validatedBottleName($0) == nil },
            "unsafe bottle override rejection"
        )

        let rejectedPaths = SecundaPaths(
            applicationSupport: root,
            repositoryRoot: sourceRoot,
            environment: [
                "SECUNDA_BOTTLE_NAME": "../SkyrimSE",
                "SECUNDA_DEVELOPER_MODE": "1"
            ]
        )
        checks.expect(
            rejectedPaths.bottleOverrideError != nil
                && !rejectedPaths.isManagedBottleRoot(rejectedPaths.bottleRoot),
            "invalid bottle override fails closed"
        )

        let packagedPaths = SecundaPaths(
            applicationSupport: root,
            repositoryRoot: nil,
            environment: ["SECUNDA_BOTTLE_NAME": "SkyrimSE-SourceClone"]
        )
        checks.expect(
            packagedPaths.bottleOverrideError != nil
                && !packagedPaths.isManagedBottleRoot(packagedPaths.bottleRoot),
            "packaged bottle override rejection"
        )
        checks.expect(
            !overridePaths.isManagedBottleRoot(root.appendingPathComponent("escaped-prefix")),
            "managed bottle containment"
        )
        checks.expect(
            RuntimeManager.developmentRuntimeOverride(
                environment: ["SECUNDA_WINE_BIN": "/tmp/dev-wine"],
                repositoryRoot: sourceRoot
            ) == nil,
            "packaged runtime override rejection"
        )
        checks.expect(
            RuntimeManager.developmentRuntimeOverride(
                environment: [
                    "SECUNDA_DEVELOPER_MODE": "1",
                    "SECUNDA_WINE_BIN": "/tmp/dev-wine"
                ],
                repositoryRoot: sourceRoot
            ) == "/tmp/dev-wine",
            "explicit development runtime override"
        )
        checks.expect(
            RuntimeManager.developmentPerformanceEnvironment(
                environment: [
                    "MTL_HUD_ENABLED": "1",
                    "SECUNDA_PERFORMANCE_CAPTURE": "1"
                ],
                repositoryRoot: nil
            ).isEmpty,
            "packaged performance telemetry rejection"
        )
        let performanceEnvironment = RuntimeManager.developmentPerformanceEnvironment(
            environment: [
                "MTL_HUD_OPACITY": "0.25",
                "SECUNDA_DEVELOPER_MODE": "1",
                "SECUNDA_PERFORMANCE_CAPTURE": "1"
            ],
            repositoryRoot: sourceRoot
        )
        checks.expect(
            performanceEnvironment["MTL_HUD_ENABLED"] == "1"
                && performanceEnvironment["MTL_HUD_LOG_ENABLED"] == "1"
                && performanceEnvironment["MTL_HUD_OPACITY"] == "0.25"
                && performanceEnvironment["MTL_HUD_LOG_SHADER_ENABLED"] == nil,
            "development Metal HUD environment"
        )
        checks.expect(
            RuntimeManager.developmentPerformanceEnvironment(
                environment: [
                    "SECUNDA_DEVELOPER_MODE": "1",
                    "SECUNDA_PERFORMANCE_CAPTURE": "1",
                    "SECUNDA_SHADER_LOGGING": "1"
                ],
                repositoryRoot: sourceRoot
            )["MTL_HUD_LOG_SHADER_ENABLED"] == "1",
            "separately gated shader telemetry"
        )
    }

    private static func checkCompatibilityProfile(checks: inout LauncherHandoffCheckSummary) {
        checks.expect(
            Set(BottleManager.gameDLLOverrides) == Set([
                "x3daudio1_6",
                "x3daudio1_7",
                "xaudio2_6",
                "xaudio2_7"
            ]),
            "Skyrim audio compatibility profile"
        )
        checks.expect(
            BottleManager.gracefulShutdownArguments == [
                "wineboot",
                "--end-session",
                "--shutdown"
            ],
            "prefix shutdown first requests a clean end session"
        )
        checks.expect(
            BottleManager.forcedShutdownArguments == [
                "wineboot",
                "--kill",
                "--shutdown"
            ],
            "prefix shutdown terminates remaining apps and the desktop"
        )
        checks.expect(
            BottleManager.initializationWaitArguments == ["-w"],
            "fresh prefix waits for Wine initialization"
        )
    }

    private static func checkRuntimeIntegrity(checks: inout LauncherHandoffCheckSummary) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("secunda-integrity-\(UUID().uuidString)", isDirectory: true)
        let executable = root.appendingPathComponent("bin/wine")
        let manifest = root.appendingPathComponent(RuntimeIntegrityPolicy.relativePath)
        try? FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: manifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data().write(to: executable)
        let validData = Data(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  ./bin/wine\n".utf8
        )
        try? validData.write(to: manifest)

        if case .valid(_, let inspectedData) = RuntimeIntegrityPolicy.inspect(runtimeRoot: root) {
            checks.expect(
                inspectedData == validData
                    && RuntimeIntegrityPolicy.validatesEntries(inspectedData, runtimeRoot: root),
                "runtime integrity manifest validation"
            )
        } else {
            checks.expect(false, "runtime integrity manifest validation")
        }
        let escapingData = Data(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  ./../outside\n".utf8
        )
        checks.expect(
            !RuntimeIntegrityPolicy.validatesEntries(escapingData, runtimeRoot: root),
            "runtime integrity path escape rejection"
        )
        let unlisted = root.appendingPathComponent("lib/unlisted-runtime-file")
        try? FileManager.default.createDirectory(
            at: unlisted.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data().write(to: unlisted)
        checks.expect(
            !RuntimeIntegrityPolicy.validatesEntries(validData, runtimeRoot: root),
            "runtime integrity requires complete file coverage"
        )
        try? FileManager.default.removeItem(at: root)
    }

    private static func checkHostPreflight(checks: inout LauncherHandoffCheckSummary) {
        let macOS15 = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        let supported = HostPreflight.evaluate(
            operatingSystem: macOS15,
            isAppleSilicon: true,
            sourceRuntimeProbeSucceeded: true,
            freeDiskBytes: HostPreflight.recommendedInstallBytes,
            needsInstallSpace: true
        )
        checks.expect(supported.isReady, "supported Mac preflight")

        let lowDisk = HostPreflight.evaluate(
            operatingSystem: macOS15,
            isAppleSilicon: true,
            sourceRuntimeProbeSucceeded: true,
            freeDiskBytes: 1,
            needsInstallSpace: true
        )
        checks.expect(isWarning(lowDisk), "low disk preflight warning")

        let unsupported = HostPreflight.evaluate(
            operatingSystem: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0),
            isAppleSilicon: true,
            sourceRuntimeProbeSucceeded: true,
            freeDiskBytes: HostPreflight.recommendedInstallBytes,
            needsInstallSpace: false
        )
        checks.expect(isFailure(unsupported), "unsupported macOS preflight")

        let lowPower = HostPreflight.evaluate(
            operatingSystem: macOS15,
            isAppleSilicon: true,
            sourceRuntimeProbeSucceeded: true,
            freeDiskBytes: HostPreflight.recommendedInstallBytes,
            needsInstallSpace: false,
            lowPowerModeEnabled: true
        )
        checks.expect(isWarning(lowPower), "Low Power Mode preflight warning")
        checks.expect(
            HostPowerProbe.lowPowerModeEnabled(in: Data(" lowpowermode 1\n".utf8)) == true
                && HostPowerProbe.lowPowerModeEnabled(in: Data(" lowpowermode 0\n".utf8)) == false,
            "host power-mode parsing"
        )
    }

    private static func checkLaunchHandoff(checks: inout LauncherHandoffCheckSummary) {
        let fixture = Data(
            "\"Steam.exe\",\"4\",\"Console\",\"1\",\"0 K\"\r\n"
                .appending("\"SkyrimSELauncher.exe\",\"8\",\"Console\",\"1\",\"0 K\"\r\n")
                .appending("\"SkyrimSE.exe\",\"12\",\"Console\",\"1\",\"0 K\"\r\n")
                .utf8
        )
        let names = WindowsProcessProbe.imageNames(from: fixture) ?? []
        checks.expect(
            names.contains("skyrimse.exe")
                && names.contains("skyrimselauncher.exe")
                && !names.contains("skyrimse.exe.backup"),
            "exact Windows process-name parsing"
        )
        checks.expect(
            WindowsProcessSnapshot(imageNames: names).handoffState == .game
                && WindowsProcessSnapshot(imageNames: ["SkyrimSELauncher.exe"]).handoffState == .launcher
                && WindowsProcessSnapshot(imageNames: ["NotSkyrimSE.exe"]).handoffState == .none,
            "game handoff state priority"
        )
        checks.expect(
            WindowsProcessProbe.imageNames(from: Data("not csv\n".utf8)) == nil,
            "malformed process snapshot rejection"
        )
        checks.expect(
            WindowsProcessProbe.filteredImageIsPresent(
                "SkyrimSE.exe",
                in: Data("\"SkyrimSE.exe\",\"12\",\"Console\",\"1\",\"0 K\"\r\n".utf8)
            ) == true
                && WindowsProcessProbe.filteredImageIsPresent(
                    "SkyrimSE.exe",
                    in: Data()
                ) == false,
            "targeted Windows process query parsing"
        )
        checks.expect(
            WindowsProcessProbe.filteredImageIsPresent(
                "SkyrimSE.exe",
                in: Data("\"Other.exe\",\"12\",\"Console\",\"1\",\"0 K\"\r\n".utf8)
            ) == nil,
            "targeted Windows process mismatch rejection"
        )
        let launchStart = Date(timeIntervalSince1970: 1_000)
        var stableLaunch = ProcessStabilityTracker(requiredStableSeconds: 10)
        checks.expect(
            stableLaunch.observe(isRunning: true, at: launchStart) == .starting
                && stableLaunch.observe(
                    isRunning: true,
                    at: launchStart.addingTimeInterval(9.9)
                ) == .starting
                && stableLaunch.observe(
                    isRunning: true,
                    at: launchStart.addingTimeInterval(10)
                ) == .stable,
            "game launch requires a stable health window"
        )
        var transientLaunch = ProcessStabilityTracker(requiredStableSeconds: 10)
        checks.expect(
            transientLaunch.observe(isRunning: false, at: launchStart) == .absent
                && transientLaunch.observe(isRunning: true, at: launchStart) == .starting
                && transientLaunch.observe(
                    isRunning: false,
                    at: launchStart.addingTimeInterval(1)
                ) == .exited,
            "transient game process is rejected"
        )
        var restartedLaunch = ProcessStabilityTracker(requiredStableSeconds: 10)
        checks.expect(
            restartedLaunch.observe(isRunning: true, at: launchStart) == .starting
                && restartedLaunch.observe(
                    isRunning: false,
                    at: launchStart.addingTimeInterval(1)
                ) == .exited
                && restartedLaunch.observe(
                    isRunning: true,
                    at: launchStart.addingTimeInterval(10)
                ) == .starting,
            "restarted image receives a fresh health window"
        )
        var authorizationHandoff = ProcessStabilityTracker(requiredStableSeconds: 0)
        checks.expect(
            authorizationHandoff.observe(isRunning: true, at: launchStart) == .stable,
            "authorization-only handoff can be immediate"
        )
        checks.expect(
            WindowsProcessProbe.isTransientQueryTimeout(
                ProcessRunnerError.captureTimedOut(15)
            ) && !WindowsProcessProbe.isTransientQueryTimeout(
                WindowsProcessProbeError.commandFailed(1)
            ),
            "Windows process polling retries only bounded query timeouts"
        )
        let visibleSurface = GameWindowSurface(
            windowID: 77,
            ownerPID: 42,
            isOnscreen: true,
            layer: 0,
            alpha: 1,
            x: 12,
            y: 34,
            width: 1280,
            height: 720
        )
        let hiddenSurface = GameWindowSurface(
            ownerPID: 42,
            isOnscreen: false,
            layer: 0,
            alpha: 1,
            width: 1280,
            height: 720
        )
        checks.expect(
            visibleSurface.isPresentable && visibleSurface.isVisible
                && visibleSurface.windowID == 77
                && visibleSurface.x == 12
                && visibleSurface.y == 34
                && hiddenSurface.isPresentable && !hiddenSurface.isVisible,
            "visible launch health retains the observed Mac surface geometry"
        )
        let fullDisplay = DisplayExtent(width: 1710, height: 1107)
        let capturedSurface = GameWindowSurface(
            ownerPID: 42,
            isOnscreen: true,
            layer: 25,
            alpha: 1,
            width: 1710,
            height: 1107
        )
        let decoratedFallback = GameWindowSurface(
            ownerPID: 42,
            isOnscreen: true,
            layer: 0,
            alpha: 1,
            x: 0,
            y: 67,
            width: 1716,
            height: 1087
        )
        checks.expect(
            capturedSurface.covers(fullDisplay)
                && !visibleSurface.covers(fullDisplay)
                && !decoratedFallback.covers(fullDisplay),
            "exclusive launch health rejects visible decorated fallbacks"
        )
        checks.expect(
            capturedSurface.isPresentable,
            "raised fullscreen game windows satisfy launch health"
        )
        checks.expect(
            !GameWindowSurface(
                ownerPID: 42,
                isOnscreen: true,
                layer: -1,
                alpha: 1,
                width: 1280,
                height: 720
            ).isPresentable
                && !GameWindowSurface(
                    ownerPID: 42,
                    isOnscreen: true,
                    layer: 0,
                    alpha: 0,
                    width: 1280,
                    height: 720
                ).isPresentable,
            "desktop-level and transparent windows cannot satisfy game launch health"
        )
        var savedClassicSettings = GameSettings()
        savedClassicSettings.displayMode = .borderlessFullscreen
        savedClassicSettings.width = 1920
        savedClassicSettings.height = 1080
        let displayGeometry = HostDisplayGeometry(
            fullFramePoints: DisplayExtent(width: 1710, height: 1107),
            fullscreenContentPoints: DisplayExtent(width: 1710, height: 1074),
            visibleFramePoints: DisplayExtent(width: 1710, height: 1005),
            windowedContentPoints: DisplayExtent(width: 1710, height: 973),
            backingScale: 2,
            activeFullscreenModePoints: DisplayExtent(width: 1710, height: 1107),
            supportsTwoXRetina: true,
            switchableFullscreenModes: [
                DisplayExtent(width: 1710, height: 1107),
                DisplayExtent(width: 1280, height: 800)
            ]
        )
        checks.expect(
            GameService.desktopFittedSettings(
                savedClassicSettings,
                descriptor: .insurgency,
                displayGeometry: displayGeometry
            ) == savedClassicSettings
                && GameService.desktopFittedSettings(
                    savedClassicSettings,
                    descriptor: .supcom2,
                    displayGeometry: displayGeometry
                ) == savedClassicSettings,
            "desktop fitting does not rewrite backing-pixel or inherited profiles"
        )
        checks.expect(
            GameService.desktopFittedSettings(
                savedClassicSettings,
                descriptor: .skyrimSE,
                displayGeometry: displayGeometry
            ) == savedClassicSettings
                && GameService.desktopFittedSettings(
                    savedClassicSettings,
                    descriptor: .insurgency,
                    displayGeometry: .unknown
                ) == savedClassicSettings,
            "desktop fitting stays scoped to opted-in point-coordinate games"
        )
        let backingBorderless = try? GameService.resolvedDisplayContract(
            settings: savedClassicSettings,
            descriptor: .insurgency,
            displayGeometry: displayGeometry
        )
        var backingExclusive = savedClassicSettings
        backingExclusive.displayMode = .exclusiveFullscreen
        backingExclusive.width = 1280
        backingExclusive.height = 800
        let lowerBackingExclusive = try? GameService.resolvedDisplayContract(
            settings: backingExclusive,
            descriptor: .insurgency,
            displayGeometry: displayGeometry
        )
        var backingWindowed = savedClassicSettings
        backingWindowed.displayMode = .windowed
        backingWindowed.width = 2560
        backingWindowed.height = 1080
        let exactBackingWindow = try? GameService.resolvedDisplayContract(
            settings: backingWindowed,
            descriptor: .insurgency,
            displayGeometry: displayGeometry
        )
        checks.expect(
            backingBorderless?.settings.width == 3420
                && backingBorderless?.settings.height == 2214
                && backingBorderless?.retinaMode == true
                && lowerBackingExclusive?.settings == backingExclusive
                && exactBackingWindow?.settings == backingWindowed,
            "backing display contract resolves borderless, exclusive, and windowed semantics"
        )
        var unsupportedBackingExclusive = backingExclusive
        unsupportedBackingExclusive.width = 1920
        unsupportedBackingExclusive.height = 1080
        let rejectsUnsupportedBackingMode: Bool
        do {
            _ = try GameService.resolvedDisplayContract(
                settings: unsupportedBackingExclusive,
                descriptor: .insurgency,
                displayGeometry: displayGeometry
            )
            rejectsUnsupportedBackingMode = false
        } catch GameLaunchError.unsupportedExclusiveResolution {
            rejectsUnsupportedBackingMode = true
        } catch {
            rejectsUnsupportedBackingMode = false
        }
        let oneXGeometry = HostDisplayGeometry(
            fullFramePoints: DisplayExtent(width: 1920, height: 1080),
            fullscreenContentPoints: DisplayExtent(width: 1920, height: 1080),
            visibleFramePoints: DisplayExtent(width: 1920, height: 1040),
            windowedContentPoints: DisplayExtent(width: 1920, height: 1008),
            backingScale: 1,
            activeFullscreenModePoints: DisplayExtent(width: 1920, height: 1080),
            supportsTwoXRetina: false,
            switchableFullscreenModes: [DisplayExtent(width: 1920, height: 1080)]
        )
        checks.expect(
            rejectsUnsupportedBackingMode
                && !GameService.sessionRetinaMode(
                    for: .insurgency,
                    displayGeometry: oneXGeometry
                )
                && GameService.sessionRetinaMode(
                    for: .insurgency,
                    displayGeometry: displayGeometry
                )
                && !GameService.sessionRetinaMode(
                    for: .skyrimSE,
                    displayGeometry: displayGeometry
                ),
            "invalid exclusive modes are rejected and Retina mapping follows the physical display"
        )
        var skyrimExclusiveSettings = savedClassicSettings
        skyrimExclusiveSettings.displayMode = .exclusiveFullscreen
        skyrimExclusiveSettings.width = 3420
        skyrimExclusiveSettings.height = 2214
        let validatedSkyrimExclusive = GameService.validatedCapturedExclusiveSettings(
            skyrimExclusiveSettings,
            descriptor: .skyrimSE,
            displayGeometry: displayGeometry
        )
        var lowerSkyrimExclusive = skyrimExclusiveSettings
        lowerSkyrimExclusive.width = 1280
        lowerSkyrimExclusive.height = 800
        checks.expect(
            validatedSkyrimExclusive.width == 1710
                && validatedSkyrimExclusive.height == 1107
                && GameService.validatedCapturedExclusiveSettings(
                    lowerSkyrimExclusive,
                    descriptor: .skyrimSE,
                    displayGeometry: displayGeometry
                ) == lowerSkyrimExclusive
                && GameService.validatedCapturedExclusiveSettings(
                    skyrimExclusiveSettings,
                    descriptor: .fallout4,
                    displayGeometry: displayGeometry
                ) == skyrimExclusiveSettings,
            "captured Skyrim keeps switchable modes and recovers stale backing-pixel modes"
        )
        var nativeBackingExclusive = backingExclusive
        nativeBackingExclusive.width = 3420
        nativeBackingExclusive.height = 2214
        checks.expect(
            GameService.requiredFullscreenCoverage(
                settings: lowerSkyrimExclusive,
                descriptor: .skyrimSE,
                displayGeometry: displayGeometry
            ) == DisplayExtent(width: 1280, height: 800)
                && GameService.requiredFullscreenCoverage(
                    settings: savedClassicSettings,
                    descriptor: .skyrimSE,
                    displayGeometry: displayGeometry
                ) == nil
                && GameService.requiredFullscreenCoverage(
                    settings: skyrimExclusiveSettings,
                    descriptor: .fallout4,
                    displayGeometry: displayGeometry
                ) == nil
                && GameService.requiredFullscreenCoverage(
                    settings: backingBorderless?.settings ?? savedClassicSettings,
                    descriptor: .insurgency,
                    displayGeometry: displayGeometry,
                    retinaMode: true
                ) == DisplayExtent(width: 1710, height: 1107)
                && GameService.requiredFullscreenCoverage(
                    settings: nativeBackingExclusive,
                    descriptor: .insurgency,
                    displayGeometry: displayGeometry,
                    retinaMode: true
                ) == DisplayExtent(width: 1710, height: 1107)
                && GameService.requiredFullscreenCoverage(
                    settings: backingExclusive,
                    descriptor: .insurgency,
                    displayGeometry: displayGeometry,
                    retinaMode: true
                ) == DisplayExtent(width: 1280, height: 800)
                && GameService.requiredFullscreenCoverage(
                    settings: backingWindowed,
                    descriptor: .insurgency,
                    displayGeometry: displayGeometry,
                    retinaMode: true
                ) == nil,
            "fullscreen health compares each mode against its physical host frame"
        )
        let gameEnvironment = GameService.gameEnvironment(
            base: ["WINEPREFIX": "/tmp/prefix"],
            descriptor: .skyrimSE
        )
        checks.expect(
            gameEnvironment["SteamAppId"] == GameDescriptor.skyrimSE.steamAppID
                && gameEnvironment["SteamGameId"] == GameDescriptor.skyrimSE.steamAppID
                && gameEnvironment["WINEPREFIX"] == "/tmp/prefix"
                && gameEnvironment["DXMT_CONFIG"] == nil,
            "Skyrim launch carries no failed DXMT experiment"
        )
        let falloutEnvironment = GameService.gameEnvironment(
            base: ["WINEPREFIX": "/tmp/prefix"],
            descriptor: .fallout4
        )
        checks.expect(
            falloutEnvironment["DXMT_CONFIG"] == "d3d11.preferredMaxFrameRate=60;",
            "Fallout 4 DXMT frame-rate cap"
        )
        let insurgencyEnvironment = GameService.gameEnvironment(
            base: ["WINEPREFIX": "/tmp/prefix"],
            descriptor: .insurgency
        )
        checks.expect(
            insurgencyEnvironment["DXMT_CONFIG"] == nil,
            "DXMT compatibility options do not bleed across titles"
        )
        let interactiveLog = URL(fileURLWithPath: "/tmp/game-launch.log")
        checks.expect(
            SteamService.launchOutput(diagnostics: false, logURL: interactiveLog) == .discard
                && GameService.launchOutput(diagnostics: false, logURL: interactiveLog) == .discard
                && SteamService.launchOutput(diagnostics: true, logURL: interactiveLog)
                    == .append(interactiveLog)
                && GameService.launchOutput(diagnostics: true, logURL: interactiveLog)
                    == .append(interactiveLog),
            "interactive launch output follows diagnostics"
        )
        checks.expect(
            GameLaunchStage.allCases == [.checking, .compatibility, .voiceAudio, .profile, .steam, .game],
            "six-stage game launch progress"
        )
    }

    private static func checkSetupJourney(
        paths: SecundaPaths,
        checks: inout LauncherHandoffCheckSummary
    ) {
        var snapshot = LauncherSnapshot.empty(paths: paths)
        checks.expect(
            SetupJourney(snapshot: snapshot, descriptor: .skyrimSE).completedSteps == 0,
            "setup journey starts empty"
        )
        snapshot.runtime = .ready("Source-only")
        snapshot.bottle = .ready("Separate")
        snapshot.steam = .ready("Files detected")
        let awaitingSteam = SetupJourney(snapshot: snapshot, descriptor: .skyrimSE)
        checks.expect(
            awaitingSteam.completedSteps == 3 && awaitingSteam.title == "Finish in Steam",
            "setup journey user handoff"
        )
        var skyrim = GameSnapshot()
        skyrim.state = .ready("Files detected")
        snapshot.games[GameDescriptor.skyrimSE.id] = skyrim
        let complete = SetupJourney(snapshot: snapshot, descriptor: .skyrimSE)
        checks.expect(
            complete.fraction == 1 && complete.label == "Setup complete",
            "setup journey completion"
        )
        checks.expect(
            SetupJourney(snapshot: snapshot, descriptor: .fallout4).completedSteps == 3,
            "setup journey is per game"
        )
    }

    private static func checkSteamInstallProbe(checks: inout LauncherHandoffCheckSummary) {
        let fixture = SteamProbeFixture()
        fixture.prepareDefaultInstall()
        checks.expect(
            isInstalled(fixture.probe.inspect(appID: "489830", executableName: "SkyrimSE.exe")),
            "complete Steam manifest detection"
        )

        fixture.makeDefaultExecutableInvalid()
        checks.expect(
            isIncomplete(fixture.probe.inspect(appID: "489830", executableName: "SkyrimSE.exe")),
            "invalid game executable rejection"
        )
        fixture.prepareDefaultInstall()

        fixture.removeDefaultBaselineData()
        checks.expect(
            isIncomplete(fixture.probe.inspect(appID: "489830", executableName: "SkyrimSE.exe")),
            "missing baseline game data rejection"
        )
        fixture.prepareDefaultInstall()

        fixture.makeDefaultInstallPartial()
        checks.expect(
            isIncomplete(fixture.probe.inspect(appID: "489830", executableName: "SkyrimSE.exe")),
            "partial Steam install rejection"
        )

        fixture.prepareCustomLibrary()
        checks.expect(
            isInstalled(fixture.probe.inspect(appID: "489830", executableName: "SkyrimSE.exe")),
            "custom Steam library detection"
        )
        fixture.prepareEscapingLibrary()
        checks.expect(
            fixture.probe.inspect(appID: "489830", executableName: "SkyrimSE.exe") == .missing,
            "external Steam library rejection"
        )
        fixture.remove()
    }

    private static func checkDocumentsIsolation(checks: inout LauncherHandoffCheckSummary) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("secunda-isolation-\(UUID().uuidString)", isDirectory: true)
        let paths = SecundaPaths(
            applicationSupport: root,
            repositoryRoot: URL(fileURLWithPath: "/tmp/secunda-source"),
            environment: [
                "SECUNDA_BOTTLE_NAME": "IsolationTest",
                "SECUNDA_DEVELOPER_MODE": "1"
            ]
        )
        let user = paths.bottleRoot.appendingPathComponent("drive_c/users/secunda", isDirectory: true)
        let documents = user.appendingPathComponent("Documents", isDirectory: true)
        let outside = root.appendingPathComponent("outside-documents", isDirectory: true)
        let sentinel = outside.appendingPathComponent("keep.txt")

        try? paths.prepareManagedDirectories()
        try? FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try? Data().write(to: paths.bottleRoot.appendingPathComponent("system.reg"))
        try? FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try? Data("preserve".utf8).write(to: sentinel)
        try? FileManager.default.createSymbolicLink(at: documents, withDestinationURL: outside)

        checks.expect(
            !BottleManager.hasPrivateDocuments(paths: paths, bottleRoot: paths.bottleRoot),
            "host Documents link is not private"
        )
        try? BottleManager.preparePrivateDocuments(paths: paths, bottleRoot: paths.bottleRoot)
        checks.expect(
            BottleManager.hasPrivateDocuments(paths: paths, bottleRoot: paths.bottleRoot),
            "private Documents provisioning"
        )
        checks.expect(
            FileManager.default.fileExists(atPath: sentinel.path),
            "host Documents target preservation"
        )
        try? FileManager.default.removeItem(at: root)
    }

    private static func checkDiagnosticRedaction(
        paths: SecundaPaths,
        checks: inout LauncherHandoffCheckSummary
    ) {
        var snapshot = LauncherSnapshot.empty(paths: paths)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        snapshot.runtimePath = home + "/SecundaRuntime/bin/wine"
        snapshot.bottlePath = home + "/Secunda/Bottles/SkyrimSE"
        var skyrimGame = GameSnapshot()
        skyrimGame.path = home + "/Secunda/SkyrimSE.exe"
        snapshot.games[GameDescriptor.skyrimSE.id] = skyrimGame
        let report = DiagnosticService(paths: paths).report(snapshot: snapshot)
        checks.expect(
            !report.contains(home + "/") && report.contains("~/SecundaRuntime"),
            "diagnostic home path redaction"
        )
        checks.expect(
            !DiagnosticService.isSafeSupportLog(URL(fileURLWithPath: "/tmp/steam-launch.log"))
                && !DiagnosticService.isSafeSupportLog(URL(fileURLWithPath: "/tmp/game-launch.log"))
                && DiagnosticService.isSafeSupportLog(URL(fileURLWithPath: "/tmp/runtime-probe.log"))
                && DiagnosticService.isSafeSupportLog(
                    URL(fileURLWithPath: "/tmp/launch-records.jsonl")
                ),
            "interactive log exclusion"
        )
    }

    private static func isInstalled(_ state: SteamGameInstallState) -> Bool {
        if case .installed = state { return true }
        return false
    }

    private static func isIncomplete(_ state: SteamGameInstallState) -> Bool {
        if case .incomplete = state { return true }
        return false
    }

    private static func isWarning(_ state: ComponentState) -> Bool {
        if case .warning = state { return true }
        return false
    }

    private static func isFailure(_ state: ComponentState) -> Bool {
        if case .failed = state { return true }
        return false
    }
}

private struct SteamProbeFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("secunda-steam-probe-\(UUID().uuidString)", isDirectory: true)

    var bottle: URL { root.appendingPathComponent("Bottle", isDirectory: true) }
    var steam: URL { bottle.appendingPathComponent("drive_c/Steam", isDirectory: true) }
    var steamApps: URL { steam.appendingPathComponent("steamapps", isDirectory: true) }
    var defaultGame: URL {
        steamApps.appendingPathComponent("common/Skyrim Special Edition", isDirectory: true)
    }
    var defaultManifest: URL { steamApps.appendingPathComponent("appmanifest_489830.acf") }
    var probe: SteamInstallProbe { SteamInstallProbe(bottleRoot: bottle, steamRoot: steam) }

    func prepareDefaultInstall() {
        try? FileManager.default.createDirectory(at: defaultGame, withIntermediateDirectories: true)
        try? Data(Self.completeManifest.utf8).write(to: defaultManifest)
        writeGamePayload(at: defaultGame)
    }

    func makeDefaultExecutableInvalid() {
        try? Data().write(to: defaultGame.appendingPathComponent("SkyrimSE.exe"))
    }

    func removeDefaultBaselineData() {
        try? FileManager.default.removeItem(at: defaultGame.appendingPathComponent("Data/Skyrim.esm"))
    }

    func makeDefaultInstallPartial() {
        let manifest = Self.completeManifest.replacingOccurrences(
            of: "\"BytesDownloaded\" \"100\"",
            with: "\"BytesDownloaded\" \"25\""
        )
        try? Data(manifest.utf8).write(to: defaultManifest)
    }

    func prepareCustomLibrary() {
        try? FileManager.default.removeItem(at: defaultManifest)
        let drive = bottle.appendingPathComponent("drive_d", isDirectory: true)
        let library = drive.appendingPathComponent("SteamLibrary", isDirectory: true)
        let apps = library.appendingPathComponent("steamapps", isDirectory: true)
        let game = apps.appendingPathComponent("common/Skyrim Special Edition", isDirectory: true)
        let dosDevices = bottle.appendingPathComponent("dosdevices", isDirectory: true)
        try? FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dosDevices, withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(
            at: dosDevices.appendingPathComponent("d:"),
            withDestinationURL: drive
        )
        try? Data("\"path\" \"D:\\\\SteamLibrary\"".utf8).write(
            to: steamApps.appendingPathComponent("libraryfolders.vdf")
        )
        try? Data(Self.completeManifest.utf8).write(
            to: apps.appendingPathComponent("appmanifest_489830.acf")
        )
        writeGamePayload(at: game)
    }

    func prepareEscapingLibrary() {
        try? FileManager.default.removeItem(at: bottle.appendingPathComponent("drive_d"))
        let outside = root.appendingPathComponent("outside-drive", isDirectory: true)
        let library = outside.appendingPathComponent("SteamLibrary", isDirectory: true)
        let apps = library.appendingPathComponent("steamapps", isDirectory: true)
        let game = apps.appendingPathComponent("common/Skyrim Special Edition", isDirectory: true)
        let dosDevices = bottle.appendingPathComponent("dosdevices", isDirectory: true)
        try? FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(
            at: dosDevices.appendingPathComponent("e:"),
            withDestinationURL: outside
        )
        try? Data("\"path\" \"E:\\\\SteamLibrary\"".utf8).write(
            to: steamApps.appendingPathComponent("libraryfolders.vdf")
        )
        try? Data(Self.completeManifest.utf8).write(
            to: apps.appendingPathComponent("appmanifest_489830.acf")
        )
        writeGamePayload(at: game)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeGamePayload(at game: URL) {
        var executable = Data(repeating: 0, count: 4_096)
        executable[0] = 0x4d
        executable[1] = 0x5a
        let dataDirectory = game.appendingPathComponent("Data", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try? executable.write(to: game.appendingPathComponent("SkyrimSE.exe"))
        try? Data([0]).write(to: dataDirectory.appendingPathComponent("Skyrim.esm"))
    }

    private static let completeManifest = """
    "AppState"
    {
        "appid" "489830"
        "StateFlags" "4"
        "installdir" "Skyrim Special Edition"
        "BytesToDownload" "100"
        "BytesDownloaded" "100"
        "BytesToStage" "100"
        "BytesStaged" "100"
    }
    """
}
