import Foundation

enum GameLaunchOutcome: Equatable, Sendable {
    case started
    case alreadyRunning
}

enum GameLaunchError: LocalizedError {
    case invalidInstallation(String)
    case steamAuthorizationTimedOut(String)
    case gameDidNotStart(String)

    var errorDescription: String? {
        switch self {
        case .invalidInstallation(let title):
            "Secunda could not safely resolve the installed \(title) executable. Refresh or verify the game in Steam."
        case .steamAuthorizationTimedOut(let title):
            "Steam did not make \(title) ready in time. Leave Steam open, finish any sign-in or update, then press Play again."
        case .gameDidNotStart(let title):
            "Steam authorized \(title), but the game did not stay running. Leave Steam open and try Play again."
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
        bottleProcessInspector: BottleProcessInspector
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

    func launch(
        runtime: RuntimeDescriptor,
        settings: GameSettings,
        diagnostics: Bool,
        screenPixelWidth: Int,
        screenPixelHeight: Int = 0,
        progress: @escaping (GameLaunchStage) async -> Void = { _ in }
    ) async throws -> GameLaunchOutcome {
        guard let game = validatedGameExecutable(in: runtime) else {
            throw GameLaunchError.invalidInstallation(descriptor.shortTitle)
        }
        await progress(.checking)
        if try await isGameRunning(runtime: runtime, diagnostics: diagnostics) {
            return .alreadyRunning
        }

        await progress(.compatibility)
        var voiceAudioActive = false
        if settings.nativeVoiceAudio {
            await progress(.voiceAudio)
            try await voiceAudioService.installIfNeeded(runtime: runtime, diagnostics: diagnostics)
            voiceAudioActive = voiceAudioService.isInstalled(bottleRoot: runtime.bottleRoot)
        }
        if descriptor.d3d9Backend == .dxvk {
            try dxvkService.installIfNeeded(runtime: runtime, diagnostics: diagnostics)
        }
        let logPixels = GameProfileWriter.sessionLogPixels(
            settings: settings,
            screenPixelWidth: screenPixelWidth,
            prefersNative: descriptor.prefersNativeSessionDPI
        )
        try await bottleManager.applyGameCompatibility(
            runtime: runtime,
            diagnostics: diagnostics,
            logPixels: logPixels,
            nativeVoiceAudio: voiceAudioActive,
            d3d9Backend: descriptor.d3d9Backend
        )
        await progress(.profile)
        let sessionSettings = GameProfileWriter.sessionSettings(
            settings,
            descriptor: descriptor,
            logPixels: logPixels,
            screenPixelWidth: screenPixelWidth,
            screenPixelHeight: screenPixelHeight
        )
        try profileWriter.apply(sessionSettings, bottleRoot: runtime.bottleRoot)

        if try await isGameRunning(runtime: runtime, diagnostics: diagnostics) {
            return .alreadyRunning
        }

        let launchEnvironment = Self.gameEnvironment(
            base: runtimeManager.environment(for: runtime, diagnostics: diagnostics),
            descriptor: descriptor
        )
        await progress(.steam)
        try steamService.launch(
            runtime: runtime,
            arguments: ["-applaunch", descriptor.steamAppID]
                + Self.gameArguments(descriptor: descriptor, settings: sessionSettings),
            diagnostics: diagnostics,
            extraEnvironment: Self.dxmtEnvironmentOverrides(for: descriptor)
        )

        let handoff = try await processProbe.waitForHandoff(
            runtime: runtime,
            diagnostics: diagnostics,
            timeoutSeconds: 90,
            gameImage: descriptor.gameImageName,
            launcherImage: descriptor.launcherImageName
        )
        switch handoff {
        case .game:
            // Warm Steam clients keep their original Unix environment, so a
            // game that needs a DXMT present cap must be restarted under ours.
            if descriptor.preferredMaxFrameRate != nil {
                _ = try await forceStop(runtime: runtime)
                break
            }
            return .started
        case .none:
            throw GameLaunchError.steamAuthorizationTimedOut(descriptor.shortTitle)
        case .launcher:
            break
        }

        if descriptor.preferredMaxFrameRate == nil,
           try await isGameRunning(runtime: runtime, diagnostics: diagnostics) {
            return .started
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
            gameImage: descriptor.gameImageName
        ) else {
            throw GameLaunchError.gameDidNotStart(descriptor.shortTitle)
        }
        return .started
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
        guard let frameRate = descriptor.preferredMaxFrameRate, frameRate > 0 else {
            return [:]
        }
        return ["DXMT_CONFIG": "d3d11.preferredMaxFrameRate=\(frameRate);"]
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
            gameImage: descriptor.gameImageName,
            launcherImage: descriptor.launcherImageName
        ).contains(descriptor.gameImageName)
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
                for: [executable.path] + Self.gameArguments(descriptor: descriptor, settings: settings)
            ),
            environment: resolvedEnvironment,
            currentDirectory: executable.deletingLastPathComponent(),
            output: Self.interactiveOutput
        )
    }

    /// Extra command-line arguments a game needs every launch. Exclusive
    /// fullscreen fails under the Mac display driver for wined3d titles, so
    /// those run windowed at the player's chosen resolution.
    static func gameArguments(descriptor: GameDescriptor, settings: GameSettings) -> [String] {
        guard descriptor.usesWindowedResolutionArguments else { return [] }
        return ["/windowed", String(settings.width), String(settings.height)]
    }
}
