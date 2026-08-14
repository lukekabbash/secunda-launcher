import Foundation

enum GameLaunchOutcome: Equatable, Sendable {
    case started
    case alreadyRunning
}

struct ResolvedGameDisplayContract: Equatable, Sendable {
    let settings: GameSettings
    let geometry: HostDisplayGeometry
    let logPixels: Int
    let retinaMode: Bool
    let requiredFullscreenCoverage: DisplayExtent?
}

enum GameLaunchError: LocalizedError {
    case invalidInstallation(String)
    case gameSpaceBusy(String)
    case steamClientNotReady(String)
    case steamAuthorizationTimedOut(String)
    case gameDidNotStart(String)
    case gameWindowNotVisible(String)
    case gameWindowNotFullscreen(String)
    case unsupportedExclusiveResolution(String, Int, Int)
    case sessionDidNotQuiesce(String)

    var errorDescription: String? {
        switch self {
        case .invalidInstallation(let title):
            "Secunda could not safely resolve the installed \(title) executable. Refresh or verify the game in Steam."
        case .gameSpaceBusy(let title):
            "Close \(title) before starting another game. Secunda keeps shared game-space settings unchanged while a title is running."
        case .steamClientNotReady(let title):
            "Steam did not stay running for \(title). Open Steam, finish any sign-in or update, then press Play again."
        case .steamAuthorizationTimedOut(let title):
            "Steam did not make \(title) ready in time. Leave Steam open, finish any sign-in or update, then press Play again."
        case .gameDidNotStart(let title):
            "Steam was running, but \(title) did not stay running. Leave Steam open and try Play again."
        case .gameWindowNotVisible(let title):
            "\(title) started, but macOS never received a visible game window. Secunda left the process alone so you can inspect or stop it safely."
        case .gameWindowNotFullscreen(let title):
            "\(title) started, but its window did not cover the display. Secunda rejected the fallback window instead of reporting false fullscreen success."
        case .unsupportedExclusiveResolution(let title, let width, let height):
            "\(width) × \(height) is not a display mode available to \(title). Choose one of the listed Exclusive Fullscreen modes; Secunda did not substitute another resolution."
        case .sessionDidNotQuiesce(let title):
            "Secunda could not establish a clean display session for \(title). No game settings were applied; stop the shared game space and try again."
        }
    }
}

enum GameLaunchStage: CaseIterable, Sendable {
    case checking
    case compatibility
    case voiceAudio
    case profile
    case steam
    case game
}

/// Detection state for one add-on inside an installed game directory.
struct DLCState: Identifiable, Equatable {
    let descriptor: DLCDescriptor
    let isInstalled: Bool

    var id: String { descriptor.id }
}

/// Drives one game: install detection, Steam handoff, profile writing,
/// launch, verification, and DLC inspection. All game identity comes from
/// the descriptor.
final class GameService {
    static let interactiveOutput: ProcessOutput = .discard

    static func launchOutput(diagnostics: Bool, logURL: URL) -> ProcessOutput {
        diagnostics ? .append(logURL) : interactiveOutput
    }

    let descriptor: GameDescriptor

    private let paths: SecundaPaths
    private let steamService: SteamService
    private let bottleManager: BottleManager
    private let profileWriter: GameProfileWriter
    private let processRunner: ProcessRunner
    private let runtimeManager: RuntimeManager
    private let processProbe: WindowsProcessProbe
    private let voiceAudioService: VoiceAudioService
    private let dxvkService: DXVKService
    private let bottleProcessInspector: BottleProcessInspector
    private let gameWindowProbe: MacGameWindowProbe
    private let gameFrameProbe = MacGameFrameProbe()

    init(
        descriptor: GameDescriptor,
        paths: SecundaPaths,
        steamService: SteamService,
        bottleManager: BottleManager,
        processRunner: ProcessRunner,
        runtimeManager: RuntimeManager,
        processProbe: WindowsProcessProbe,
        voiceAudioService: VoiceAudioService,
        dxvkService: DXVKService,
        bottleProcessInspector: BottleProcessInspector,
        gameWindowProbe: MacGameWindowProbe
    ) {
        self.descriptor = descriptor
        self.paths = paths
        self.steamService = steamService
        self.bottleManager = bottleManager
        self.profileWriter = GameProfileWriter(paths: paths, descriptor: descriptor)
        self.processRunner = processRunner
        self.runtimeManager = runtimeManager
        self.processProbe = processProbe
        self.voiceAudioService = voiceAudioService
        self.dxvkService = dxvkService
        self.bottleProcessInspector = bottleProcessInspector
        self.gameWindowProbe = gameWindowProbe
    }

    /// Hard OS-level stop for this game's processes, working even when
    /// wineserver is dead and they are orphaned. Returns the kill count.
    func forceStop(runtime: RuntimeDescriptor) async throws -> Int {
        let processes = try await bottleProcessInspector.runningProcesses(
            for: descriptor,
            runtime: runtime
        )
        await bottleProcessInspector.forceKill(processes)
        return processes.count
    }

    func executable(in runtime: RuntimeDescriptor?) -> URL? {
        if case .installed(let executable) = installation(in: runtime) {
            return executable
        }
        return nil
    }

    func installation(in runtime: RuntimeDescriptor?) -> SteamGameInstallState {
        guard let runtime, let steam = steamService.executable(in: runtime) else {
            return .missing
        }
        return SteamInstallProbe(
            bottleRoot: runtime.bottleRoot,
            steamRoot: steam.deletingLastPathComponent()
        ).inspect(
            appID: descriptor.steamAppID,
            executableName: descriptor.executableRelativePath,
            baselineDataFile: descriptor.baselineDataFile,
            displayName: descriptor.shortTitle
        )
    }

    func dlcStates(in runtime: RuntimeDescriptor?) -> [DLCState] {
        guard let executable = executable(in: runtime) else {
            return descriptor.dlc.map { DLCState(descriptor: $0, isInstalled: false) }
        }
        let gameRoot = executable.deletingLastPathComponent()
        return descriptor.dlc.map { dlc in
            DLCState(
                descriptor: dlc,
                isInstalled: FileManager.default.fileExists(
                    atPath: gameRoot.appendingPathComponent(dlc.detectionFile).path
                )
            )
        }
    }

    func managedINIProfilesDetected(in runtime: RuntimeDescriptor?) -> Bool {
        guard !descriptor.managedINIProfiles.isEmpty,
              let executable = executable(in: runtime),
              let installRoot = descriptor.installationRoot(containing: executable)
        else { return false }
        let root = installRoot.standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        return descriptor.managedINIProfiles.allSatisfy { profile in
            let target = root.appendingPathComponent(profile.relativePath).standardizedFileURL
            guard target.path.hasPrefix(root.path + "/"),
                target.resolvingSymlinksInPath().standardizedFileURL.path
                    .hasPrefix(resolvedRoot.path + "/"),
                let values = try? target.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
            ]), values.isRegularFile == true,
                values.isSymbolicLink != true,
                let data = try? Data(contentsOf: target),
                let contents = String(data: data, encoding: .utf8)
            else { return false }
            return GameProfileWriter.containsManagedFields(profile, in: contents)
        }
    }

    func launch(
        runtime: RuntimeDescriptor,
        settings: GameSettings,
        diagnostics: Bool,
        displayGeometry: HostDisplayGeometry,
        progress: @escaping (GameLaunchStage) async -> Void = { _ in }
    ) async throws -> GameLaunchOutcome {
        guard let game = validatedGameExecutable(in: runtime) else {
            throw GameLaunchError.invalidInstallation(descriptor.shortTitle)
        }
        let installRoot = descriptor.installationRoot(containing: game)
        let diagnosticAttemptID = GameLaunchRecorder.makeAttemptID(diagnostics: diagnostics)
        var displayContract = try Self.resolvedDisplayContract(
            settings: settings,
            descriptor: descriptor,
            displayGeometry: displayGeometry
        )
        await progress(.checking)
        if try await isGameRunning(runtime: runtime, diagnostics: diagnostics) {
            return try await confirmedLaunch(
                .alreadyRunning,
                runtime: runtime,
                timeoutSeconds: 8,
                diagnostics: diagnostics,
                attemptID: diagnosticAttemptID,
                installRoot: installRoot,
                requiredFullscreenCoverage: displayContract.requiredFullscreenCoverage
            )
        }
        if let active = try await activeGame(runtime: runtime) {
            if Self.sharesProcessIdentity(active, descriptor) {
                return try await confirmedLaunch(
                    .alreadyRunning,
                    runtime: runtime,
                    timeoutSeconds: 8,
                    diagnostics: diagnostics,
                    attemptID: diagnosticAttemptID,
                    installRoot: installRoot,
                    requiredFullscreenCoverage: displayContract.requiredFullscreenCoverage
                )
            }
            throw GameLaunchError.gameSpaceBusy(active.shortTitle)
        }
        var sessionEnvironment = runtimeManager.environment(
            for: runtime,
            diagnostics: diagnostics,
            sessionScope: Self.displaySessionScope(
                descriptor: descriptor,
                contract: displayContract
            )
        )
        try await ensureTrustedSessionEnvironment(
            runtime: runtime,
            diagnostics: diagnostics,
            expectedEnvironment: sessionEnvironment
        )

        // A stale captured mode can change the geometry sampled before the
        // old session stops. Re-sample the physical display Wine owns, then
        // establish the final process-latched contract before any writes.
        if descriptor.launchProfile.displayCoordinatePolicy == .backingPixels {
            let refreshed = HostDisplayGeometryProbe.wineMainDisplay()
            let refreshedContract = try Self.resolvedDisplayContract(
                settings: settings,
                descriptor: descriptor,
                displayGeometry: refreshed
            )
            let refreshedEnvironment = runtimeManager.environment(
                for: runtime,
                diagnostics: diagnostics,
                sessionScope: Self.displaySessionScope(
                    descriptor: descriptor,
                    contract: refreshedContract
                )
            )
            if refreshedEnvironment[RuntimeManager.sessionFingerprintKey]
                != sessionEnvironment[RuntimeManager.sessionFingerprintKey] {
                try await ensureTrustedSessionEnvironment(
                    runtime: runtime,
                    diagnostics: diagnostics,
                    expectedEnvironment: refreshedEnvironment
                )
            }
            displayContract = refreshedContract
            sessionEnvironment = refreshedEnvironment
        }

        let sessionSettings = displayContract.settings
        let logPixels = displayContract.logPixels
        let sessionRetinaMode = displayContract.retinaMode
        let effectiveDisplayGeometry = displayContract.geometry
        let executableDisplayPolicies = Self.executableDisplayPolicies(
            descriptor: descriptor,
            displayMode: sessionSettings.displayMode
        )
        let usesLegacyMacDecoration = descriptor.usesScreenCoveringBorderlessSurface
            && executableDisplayPolicies.isEmpty
        let launchEnvironment = Self.gameEnvironment(
            base: sessionEnvironment,
            descriptor: descriptor
        )

        await progress(.compatibility)
        var voiceAudioActive = false
        if descriptor.usesNativeVoiceAudioFix && settings.nativeVoiceAudio {
            await progress(.voiceAudio)
            try await voiceAudioService.installIfNeeded(runtime: runtime, diagnostics: diagnostics)
            voiceAudioActive = voiceAudioService.isInstalled(bottleRoot: runtime.bottleRoot)
        }
        if descriptor.d3d9Backend == .dxvk {
            try dxvkService.installIfNeeded(runtime: runtime, diagnostics: diagnostics)
        }
        try await bottleManager.applyGameCompatibility(
            runtime: runtime,
            diagnostics: diagnostics,
            logPixels: logPixels,
            retinaMode: sessionRetinaMode,
            nativeVoiceAudio: voiceAudioActive,
            d3d9Backend: descriptor.d3d9Backend,
            macDriverApplication: usesLegacyMacDecoration
                ? descriptor.gameImageName
                : nil,
            macDriverDecorated: usesLegacyMacDecoration
                ? sessionSettings.displayMode != .borderlessFullscreen
                : nil,
            executableDisplayPolicies: executableDisplayPolicies,
            environment: sessionEnvironment
        )
        await progress(.profile)
        try profileWriter.apply(
            sessionSettings,
            bottleRoot: runtime.bottleRoot,
            installRoot: descriptor.installationRoot(containing: game)
        )

        if try await isGameRunning(runtime: runtime, diagnostics: diagnostics) {
            return try await confirmedLaunch(
                .alreadyRunning,
                runtime: runtime,
                timeoutSeconds: 8,
                diagnostics: diagnostics,
                attemptID: diagnosticAttemptID,
                installRoot: installRoot,
                requiredFullscreenCoverage: displayContract.requiredFullscreenCoverage
            )
        }

        let gameArguments = Self.gameArguments(
            descriptor: descriptor,
            settings: sessionSettings
        )
        let recordedArguments = descriptor.steamRunningDirectLaunch == nil
            ? ["-applaunch", descriptor.steamAppID] + gameArguments
            : Self.directGameArguments(descriptor: descriptor, settings: sessionSettings)
        GameLaunchRecorder(paths: paths).recordRequest(
            descriptor: descriptor,
            settings: sessionSettings,
            arguments: recordedArguments,
            logPixels: logPixels,
            retinaMode: sessionRetinaMode,
            bottleRoot: runtime.bottleRoot,
            installRoot: installRoot,
            requestedSettings: settings,
            displayGeometry: effectiveDisplayGeometry,
            sessionFingerprint: launchEnvironment[RuntimeManager.sessionFingerprintKey],
            attemptID: diagnosticAttemptID,
            diagnostics: diagnostics
        )
        if let directLaunch = descriptor.steamRunningDirectLaunch {
            return try await launchThroughRunningSteam(
                game,
                directLaunch: directLaunch,
                runtime: runtime,
                settings: sessionSettings,
                diagnostics: diagnostics,
                sessionEnvironment: sessionEnvironment,
                gameEnvironment: launchEnvironment,
                attemptID: diagnosticAttemptID,
                installRoot: installRoot,
                requiredFullscreenCoverage: displayContract.requiredFullscreenCoverage,
                progress: progress
            )
        }

        await progress(.steam)
        try steamService.launch(
            runtime: runtime,
            arguments: ["-applaunch", descriptor.steamAppID] + gameArguments,
            diagnostics: diagnostics,
            environment: sessionEnvironment
        )

        let handoff = try await processProbe.waitForHandoff(
            runtime: runtime,
            diagnostics: diagnostics,
            timeoutSeconds: 90,
            gameImages: descriptor.gameProcessImageNames,
            launcherImages: descriptor.launcherProcessImageNames,
            requiredStableSeconds: descriptor.preferredMaxFrameRate == nil
                ? WindowsProcessProbe.requiredStableGameSeconds
                : 0
        )
        switch handoff {
        case .game:
            // Warm Steam clients keep their original Unix environment, so a
            // game that needs a DXMT present cap must be restarted under ours.
            if descriptor.preferredMaxFrameRate != nil {
                _ = try await forceStop(runtime: runtime)
                break
            }
            return try await confirmedLaunch(
                .started,
                runtime: runtime,
                diagnostics: diagnostics,
                attemptID: diagnosticAttemptID,
                installRoot: installRoot,
                requiredFullscreenCoverage: displayContract.requiredFullscreenCoverage
            )
        case .gameExited:
            throw GameLaunchError.gameDidNotStart(descriptor.shortTitle)
        case .none:
            throw GameLaunchError.steamAuthorizationTimedOut(descriptor.shortTitle)
        case .launcher:
            break
        }

        if descriptor.preferredMaxFrameRate == nil,
           try await isGameRunning(runtime: runtime, diagnostics: diagnostics) {
            return try await confirmedLaunch(
                .started,
                runtime: runtime,
                diagnostics: diagnostics,
                attemptID: diagnosticAttemptID,
                installRoot: installRoot,
                requiredFullscreenCoverage: displayContract.requiredFullscreenCoverage
            )
        }

        await progress(.game)
        try launchGameExecutable(
            game,
            runtime: runtime,
            settings: sessionSettings,
            diagnostics: diagnostics,
            environment: launchEnvironment
        )
        guard try await processProbe.waitForGame(
            runtime: runtime,
            diagnostics: diagnostics,
            timeoutSeconds: 20,
            gameImages: descriptor.gameProcessImageNames
        ) else {
            throw GameLaunchError.gameDidNotStart(descriptor.shortTitle)
        }
        return try await confirmedLaunch(
            .started,
            runtime: runtime,
            diagnostics: diagnostics,
            attemptID: diagnosticAttemptID,
            installRoot: installRoot,
            requiredFullscreenCoverage: displayContract.requiredFullscreenCoverage
        )
    }

    /// A game handed to a warm Steam client runs under that client's
    /// original Unix environment, not the one computed for this launch.
    /// Every Secunda session is stamped with a fingerprint of its launch
    /// variables; a warm wineserver stamped differently — or not at all,
    /// as after a manual or experimental cold start — is shut down here so
    /// the launch continues into a session owned by current settings.
    private func ensureTrustedSessionEnvironment(
        runtime: RuntimeDescriptor,
        diagnostics: Bool,
        expectedEnvironment: [String: String]
    ) async throws {
        let expected = expectedEnvironment[RuntimeManager.sessionFingerprintKey]
        guard try await bottleProcessInspector.sessionRequiresRestart(
            runtime: runtime,
            expectedFingerprint: expected
        ) else { return }

        do {
            try await bottleManager.shutdown(runtime: runtime, diagnostics: diagnostics)
        } catch {
            let owned = try await bottleProcessInspector.processesInBottle(runtime: runtime)
            await bottleProcessInspector.forceKill(owned)
            do {
                try await bottleManager.shutdown(runtime: runtime, diagnostics: diagnostics)
            } catch {
                throw GameLaunchError.sessionDidNotQuiesce(descriptor.shortTitle)
            }
        }
        // A session-wide display change is committed only after this exact
        // bottle is quiet. Runtime provenance alone cannot authorize kills:
        // another bottle may use the same source runtime concurrently.
        let survivors = try await bottleProcessInspector.processesInBottle(runtime: runtime)
        if !survivors.isEmpty {
            await bottleProcessInspector.forceKill(survivors)
            do {
                try await bottleManager.shutdown(runtime: runtime, diagnostics: diagnostics)
            } catch {
                throw GameLaunchError.sessionDidNotQuiesce(descriptor.shortTitle)
            }
        }
        guard try await bottleProcessInspector.waitForBottleQuiescence(runtime: runtime) else {
            throw GameLaunchError.sessionDidNotQuiesce(descriptor.shortTitle)
        }
    }

    /// Restart unless the live session carries the exact expected stamp.
    /// An unreadable or missing stamp means "cannot verify", never "clean".
    static func sessionRequiresRestart(live: String?, expected: String?) -> Bool {
        guard let expected else { return false }
        return live != expected
    }

    /// Process-latched display state is part of every shared session stamp.
    /// Player resolution and mode remain launch inputs and do not force a
    /// cold handoff unless they change the physical mode Wine initializes in.
    static func displaySessionScope(
        descriptor: GameDescriptor,
        contract: ResolvedGameDisplayContract
    ) -> String {
        var fields = [
            "display-v2",
            "dpi\(contract.logPixels)",
            contract.retinaMode ? "retina" : "points"
        ]
        if descriptor.launchProfile.displayCoordinatePolicy == .backingPixels {
            if let active = contract.geometry.activeFullscreenModePoints {
                fields.append("original\(active.width)x\(active.height)")
            }
            fields.append(
                "backing\(contract.geometry.fullFramePixels.width)x"
                    + "\(contract.geometry.fullFramePixels.height)"
            )
        }
        return fields.joined(separator: ":")
    }

    static func sessionRetinaMode(
        for descriptor: GameDescriptor,
        displayGeometry: HostDisplayGeometry
    ) -> Bool {
        switch descriptor.launchProfile.displayCoordinatePolicy {
        case .backingPixels:
            displayGeometry.supportsTwoXRetina
        case .inherited:
            !descriptor.prefersNativeSessionDPI
        }
    }

    static func resolvedDisplayContract(
        settings: GameSettings,
        descriptor: GameDescriptor,
        displayGeometry: HostDisplayGeometry
    ) throws -> ResolvedGameDisplayContract {
        let retinaMode = sessionRetinaMode(
            for: descriptor,
            displayGeometry: displayGeometry
        )
        let coordinateSettings = try backingPixelDisplaySettings(
            settings,
            descriptor: descriptor,
            displayGeometry: displayGeometry,
            retinaMode: retinaMode
        )
        let validatedSettings = validatedCapturedExclusiveSettings(
            coordinateSettings,
            descriptor: descriptor,
            displayGeometry: displayGeometry
        )
        let fittedSettings = desktopFittedSettings(
            validatedSettings,
            descriptor: descriptor,
            displayGeometry: displayGeometry
        )
        let logPixels = GameProfileWriter.sessionLogPixels(
            settings: fittedSettings,
            screenPixelWidth: displayGeometry.fullFramePixels.width,
            prefersNative: descriptor.prefersNativeSessionDPI,
            managesResolution: descriptor.managedDisplayCapabilities.resolution
        )
        let sessionSettings = GameProfileWriter.sessionSettings(
            fittedSettings,
            descriptor: descriptor,
            logPixels: logPixels,
            screenPointWidth: displayGeometry.fullFramePoints.width,
            screenPointHeight: displayGeometry.fullFramePoints.height,
            preservesRequestedResolution: descriptor.launchProfile.displayCoordinatePolicy
                == .backingPixels
        )
        return ResolvedGameDisplayContract(
            settings: sessionSettings,
            geometry: displayGeometry,
            logPixels: logPixels,
            retinaMode: retinaMode,
            requiredFullscreenCoverage: requiredFullscreenCoverage(
                settings: sessionSettings,
                descriptor: descriptor,
                displayGeometry: displayGeometry,
                retinaMode: retinaMode
            )
        )
    }

    /// Backing-pixel sessions use normal game semantics: borderless follows
    /// the desktop, exclusive selects a real physical mode, and windowed
    /// preserves the chosen client pixels and aspect ratio exactly.
    static func backingPixelDisplaySettings(
        _ settings: GameSettings,
        descriptor: GameDescriptor,
        displayGeometry: HostDisplayGeometry,
        retinaMode: Bool
    ) throws -> GameSettings {
        guard descriptor.launchProfile.displayCoordinatePolicy == .backingPixels else {
            return settings
        }
        var resolved = settings
        switch settings.displayMode {
        case .borderlessFullscreen:
            guard let active = displayGeometry.wineActiveFullscreenMode(
                retinaMode: retinaMode
            ) else { return settings }
            resolved.width = active.width
            resolved.height = active.height
        case .exclusiveFullscreen:
            let requested = DisplayExtent(width: settings.width, height: settings.height)
            let modes = displayGeometry.wineFullscreenModes(retinaMode: retinaMode)
            guard modes.isEmpty || modes.contains(requested) else {
                throw GameLaunchError.unsupportedExclusiveResolution(
                    descriptor.shortTitle,
                    settings.width,
                    settings.height
                )
            }
        case .windowed:
            break
        }
        return resolved
    }

    /// Some vendor wrappers cannot run in the source runtime. Keep Steam
    /// active for ownership/Steamworks, but launch the verified native game
    /// image directly so Steam can never queue that wrapper behind us.
    private func launchThroughRunningSteam(
        _ game: URL,
        directLaunch: SteamRunningDirectLaunch,
        runtime: RuntimeDescriptor,
        settings: GameSettings,
        diagnostics: Bool,
        sessionEnvironment: [String: String],
        gameEnvironment: [String: String],
        attemptID: String?,
        installRoot: URL?,
        requiredFullscreenCoverage: DisplayExtent?,
        progress: @escaping (GameLaunchStage) async -> Void
    ) async throws -> GameLaunchOutcome {
        await progress(.steam)
        try steamService.launch(
            runtime: runtime,
            diagnostics: diagnostics,
            environment: sessionEnvironment
        )
        let steamHandoff = try await processProbe.waitForHandoff(
            runtime: runtime,
            diagnostics: diagnostics,
            timeoutSeconds: directLaunch.steamReadyTimeoutSeconds,
            gameImages: ["steam.exe"],
            launcherImages: [],
            requiredStableSeconds: 2
        )
        guard steamHandoff == .game else {
            throw GameLaunchError.steamClientNotReady(descriptor.shortTitle)
        }

        await progress(.game)
        try launchGameExecutable(
            game,
            runtime: runtime,
            settings: settings,
            diagnostics: diagnostics,
            environment: gameEnvironment
        )
        guard try await processProbe.waitForGame(
            runtime: runtime,
            diagnostics: diagnostics,
            timeoutSeconds: 20,
            gameImages: descriptor.gameProcessImageNames
        ) else {
            throw GameLaunchError.gameDidNotStart(descriptor.shortTitle)
        }
        return try await confirmedLaunch(
            .started,
            runtime: runtime,
            diagnostics: diagnostics,
            attemptID: attemptID,
            installRoot: installRoot,
            requiredFullscreenCoverage: requiredFullscreenCoverage
        )
    }

    /// Some renderers create a healthy background process while failing to
    /// publish any usable surface. Only the profiles that opt in pay this
    /// extra launch-health cost.
    private func confirmedLaunch(
        _ outcome: GameLaunchOutcome,
        runtime: RuntimeDescriptor,
        timeoutSeconds: TimeInterval = 45,
        diagnostics: Bool,
        attemptID: String?,
        installRoot: URL?,
        requiredFullscreenCoverage: DisplayExtent? = nil
    ) async throws -> GameLaunchOutcome {
        guard descriptor.launchProfile.requiresVisibleWindow else { return outcome }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastVisibleSurface: GameWindowSurface?
        repeat {
            try Task.checkCancellation()
            let processes = try await bottleProcessInspector.runningProcesses(
                for: descriptor,
                runtime: runtime
            )
            let surfaces = gameWindowProbe.surfaces(
                ownedBy: Set(processes.map(\.pid))
            ).filter(\.isPresentable)

            if let visible = surfaces.first(where: \.isVisible) {
                lastVisibleSurface = visible
                gameWindowProbe.bringForward(ownerPID: visible.ownerPID)
                let coversRequiredDisplay = requiredFullscreenCoverage
                    .map { visible.covers($0) } ?? true
                if coversRequiredDisplay {
                    await recordFrameOutcome(
                        outcome: outcome,
                        surface: visible,
                        attemptID: attemptID,
                        diagnostics: diagnostics,
                        runtime: runtime,
                        installRoot: installRoot
                    )
                    return outcome
                }
            }
            if let hidden = surfaces.first {
                gameWindowProbe.bringForward(ownerPID: hidden.ownerPID)
            }
            if processes.isEmpty || Date() >= deadline { break }
            try await Task.sleep(for: .milliseconds(500))
        } while true
        await recordFrameOutcome(
            outcome: nil,
            surface: lastVisibleSurface,
            attemptID: attemptID,
            diagnostics: diagnostics,
            runtime: runtime,
            installRoot: installRoot
        )
        if requiredFullscreenCoverage != nil, lastVisibleSurface != nil {
            throw GameLaunchError.gameWindowNotFullscreen(descriptor.shortTitle)
        }
        throw GameLaunchError.gameWindowNotVisible(descriptor.shortTitle)
    }

    private func recordFrameOutcome(
        outcome: GameLaunchOutcome?,
        surface: GameWindowSurface?,
        attemptID: String?,
        diagnostics: Bool,
        runtime: RuntimeDescriptor,
        installRoot: URL?
    ) async {
        guard GameLaunchRecorder.recordsFrameOutcome(
            for: descriptor,
            diagnostics: diagnostics
        ) else { return }
        let frame = if let surface {
            await gameFrameProbe.observe(surface: surface)
        } else {
            GameFrameObservation.unavailable(.windowUnavailable)
        }
        GameLaunchRecorder(paths: paths).recordFrameOutcome(
            descriptor: descriptor,
            attemptID: attemptID,
            launchOutcome: outcome,
            surface: surface,
            frame: frame,
            bottleRoot: runtime.bottleRoot,
            installRoot: installRoot,
            diagnostics: diagnostics
        )
    }

    func requestVerification(runtime: RuntimeDescriptor, diagnostics: Bool) throws {
        try steamService.launch(
            runtime: runtime,
            arguments: ["steam://validate/\(descriptor.steamAppID)"],
            diagnostics: diagnostics
        )
    }

    func requestInstall(runtime: RuntimeDescriptor, diagnostics: Bool) throws {
        try steamService.launch(
            runtime: runtime,
            arguments: ["steam://install/\(descriptor.steamAppID)"],
            diagnostics: diagnostics
        )
    }

    func requestUninstall(runtime: RuntimeDescriptor, diagnostics: Bool) throws {
        try steamService.launch(
            runtime: runtime,
            arguments: ["steam://uninstall/\(descriptor.steamAppID)"],
            diagnostics: diagnostics
        )
    }

    func requestDLCInstall(
        _ dlc: DLCDescriptor,
        runtime: RuntimeDescriptor,
        diagnostics: Bool
    ) throws {
        guard let appID = dlc.steamAppID else { return }
        try steamService.launch(
            runtime: runtime,
            arguments: ["steam://install/\(appID)"],
            diagnostics: diagnostics
        )
    }

    static func gameEnvironment(
        base: [String: String],
        descriptor: GameDescriptor
    ) -> [String: String] {
        var environment = base
        environment["SteamAppId"] = descriptor.steamAppID
        environment["SteamGameId"] = descriptor.steamAppID
        environment.merge(dxmtEnvironmentOverrides(for: descriptor)) { _, new in new }
        return environment
    }

    /// DXMT config fragments that must land on the game process itself.
    static func dxmtEnvironmentOverrides(for descriptor: GameDescriptor) -> [String: String] {
        var fragments = descriptor.launchProfile.dxmtConfigFragments
        if let frameRate = descriptor.preferredMaxFrameRate, frameRate > 0 {
            fragments.append("d3d11.preferredMaxFrameRate=\(frameRate)")
        }
        guard !fragments.isEmpty else { return [:] }
        return ["DXMT_CONFIG": fragments.joined(separator: ";") + ";"]
    }

    static func executableDisplayPolicy(
        descriptor: GameDescriptor,
        displayMode: DisplayMode
    ) -> ExecutableDisplayPolicy? {
        executableDisplayPolicies(
            descriptor: descriptor,
            displayMode: displayMode
        ).first
    }

    static func executableDisplayPolicies(
        descriptor: GameDescriptor,
        displayMode: DisplayMode
    ) -> [ExecutableDisplayPolicy] {
        guard descriptor.launchProfile.exclusiveFullscreenPolicy == .capturedHostMode else {
            return []
        }
        return descriptor.gameProcessImageNames.map { application in
            ExecutableDisplayPolicy(
                application: application,
                decorated: displayMode == .windowed,
                capturesDisplaysForFullscreen: displayMode == .exclusiveFullscreen
            )
        }
    }

    static func requiredFullscreenCoverage(
        settings: GameSettings,
        descriptor: GameDescriptor,
        displayGeometry: HostDisplayGeometry,
        retinaMode: Bool = false
    ) -> DisplayExtent? {
        guard settings.displayMode != .windowed else { return nil }
        if descriptor.launchProfile.requiresFullDisplayCoverage {
            if settings.displayMode == .exclusiveFullscreen,
               descriptor.launchProfile.displayCoordinatePolicy == .backingPixels {
                let selected = DisplayExtent(width: settings.width, height: settings.height)
                let hostFrame = displayGeometry.hostFrame(
                    forWineMode: selected,
                    retinaMode: retinaMode
                )
                return hostFrame.isUsable ? hostFrame : nil
            }
            let hostFrame = displayGeometry.fullFramePoints
            return hostFrame.isUsable ? hostFrame : nil
        }
        guard settings.displayMode == .exclusiveFullscreen,
              descriptor.launchProfile.exclusiveFullscreenPolicy == .capturedHostMode
        else { return nil }
        let requested = DisplayExtent(width: settings.width, height: settings.height)
        return requested.isUsable ? requested : displayGeometry.fullFramePoints
    }

    /// Existing point-coordinate profiles keep their accepted recovery rule.
    /// Backing-coordinate profiles are validated without substitution by the
    /// display-contract resolver before reaching this path.
    static func validatedCapturedExclusiveSettings(
        _ settings: GameSettings,
        descriptor: GameDescriptor,
        displayGeometry: HostDisplayGeometry
    ) -> GameSettings {
        guard settings.displayMode == .exclusiveFullscreen,
              descriptor.launchProfile.exclusiveFullscreenPolicy == .capturedHostMode
        else { return settings }
        guard descriptor.launchProfile.displayCoordinatePolicy != .backingPixels else {
            return settings
        }

        let requested = DisplayExtent(width: settings.width, height: settings.height)
        if displayGeometry.switchableFullscreenModes.contains(requested) {
            return settings
        }
        guard displayGeometry.fullFramePoints.isUsable else { return settings }
        var adjusted = settings
        adjusted.width = displayGeometry.fullFramePoints.width
        adjusted.height = displayGeometry.fullFramePoints.height
        return adjusted
    }

    /// Games whose resolution rides the command line (-w/-h) render into the
    /// desktop Wine's Mac driver exposes in host points. Transition-safe
    /// borderless sessions use a client that fits windowed and shares the
    /// safe fullscreen aspect; ordinary windows keep the selected aspect and
    /// shrink only when their decorated frame would exceed the work area.
    static func desktopFittedSettings(
        _ settings: GameSettings,
        descriptor: GameDescriptor,
        displayGeometry: HostDisplayGeometry
    ) -> GameSettings {
        guard descriptor.launchProfile.fitsResolutionToDesktop,
              let maximum = displayGeometry.maximumContent(for: settings.displayMode)
        else { return settings }
        var fitted = settings
        let content = settings.displayMode == .borderlessFullscreen
                && descriptor.launchProfile.usesTransitionSafeBorderlessSurface
            ? (displayGeometry.transitionSafeBorderlessContent ?? maximum)
            : maximum.fitting(
                DisplayExtent(width: settings.width, height: settings.height)
            )
        fitted.width = content.width
        fitted.height = content.height
        return fitted
    }

    private func validatedGameExecutable(in runtime: RuntimeDescriptor) -> URL? {
        guard case .installed(let executable) = installation(in: runtime),
              paths.contains(executable, inBottleRoot: runtime.bottleRoot),
              let values = try? executable.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
              ]),
              values.isRegularFile == true,
              values.isSymbolicLink != true
        else {
            return nil
        }
        return executable
    }

    private func isGameRunning(
        runtime: RuntimeDescriptor,
        diagnostics: Bool
    ) async throws -> Bool {
        try await processProbe.snapshot(
            runtime: runtime,
            diagnostics: diagnostics,
            gameImages: descriptor.gameProcessImageNames,
            launcherImages: descriptor.launcherProcessImageNames
        ).containsAny(descriptor.gameProcessImageNames)
    }

    private func activeGame(runtime: RuntimeDescriptor) async throws -> GameDescriptor? {
        let processes = try await bottleProcessInspector.processesInBottle(runtime: runtime)
        return Self.activeGame(in: processes)
    }

    static func activeGame(
        in processes: [BottleProcess],
        descriptors: [GameDescriptor] = GameDescriptor.supported
    ) -> GameDescriptor? {
        descriptors.first { candidate in
            processes.contains { process in
                BottleProcessInspector.matchesImages(
                    process.command,
                    images: candidate.processImageNames
                )
            }
        }
    }

    static func sharesProcessIdentity(
        _ first: GameDescriptor,
        _ second: GameDescriptor
    ) -> Bool {
        let firstImages = Set(first.processImageNames.map { $0.lowercased() })
        let secondImages = Set(second.processImageNames.map { $0.lowercased() })
        return !firstImages.isDisjoint(with: secondImages)
    }

    private func launchGameExecutable(
        _ executable: URL,
        runtime: RuntimeDescriptor,
        settings: GameSettings,
        diagnostics: Bool,
        environment: [String: String]? = nil
    ) throws {
        let resolvedEnvironment = environment ?? Self.gameEnvironment(
            base: runtimeManager.environment(for: runtime, diagnostics: diagnostics),
            descriptor: descriptor
        )
        try processRunner.launch(
            executable: runtime.wineExecutable,
            arguments: runtime.wineArguments(
                for: [executable.path]
                    + Self.directGameArguments(descriptor: descriptor, settings: settings)
            ),
            environment: resolvedEnvironment,
            currentDirectory: executable.deletingLastPathComponent(),
            output: Self.launchOutput(
                diagnostics: diagnostics,
                logURL: paths.logsDirectory.appendingPathComponent("game-launch-\(descriptor.id).log")
            )
        )
    }

    /// Exact descriptor-owned arguments for Steam's launch request.
    static func gameArguments(descriptor: GameDescriptor, settings: GameSettings) -> [String] {
        descriptor.launchProfile.arguments(settings: settings)
    }

    static func directGameArguments(
        descriptor: GameDescriptor,
        settings: GameSettings
    ) -> [String] {
        (descriptor.steamRunningDirectLaunch?.arguments ?? [])
            + gameArguments(descriptor: descriptor, settings: settings)
    }
}
