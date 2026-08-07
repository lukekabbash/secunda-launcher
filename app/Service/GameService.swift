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

    init(
        descriptor: GameDescriptor,
        paths: SecundaPaths,
        steamService: SteamService,
        bottleManager: BottleManager,
        processRunner: ProcessRunner,
        runtimeManager: RuntimeManager,
        processProbe: WindowsProcessProbe,
        voiceAudioService: VoiceAudioService
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
        try await bottleManager.applyGameCompatibility(
            runtime: runtime,
            diagnostics: diagnostics,
            logPixels: GameProfileWriter.sessionLogPixels(
                settings: settings,
                screenPixelWidth: screenPixelWidth
            ),
            nativeVoiceAudio: voiceAudioActive
        )
        await progress(.profile)
        try profileWriter.apply(settings, bottleRoot: runtime.bottleRoot)

        if try await isGameRunning(runtime: runtime, diagnostics: diagnostics) {
            return .alreadyRunning
        }

        await progress(.steam)
        try steamService.launch(
            runtime: runtime,
            arguments: ["-applaunch", descriptor.steamAppID],
            diagnostics: diagnostics
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
            return .started
        case .none:
            throw GameLaunchError.steamAuthorizationTimedOut(descriptor.shortTitle)
        case .launcher:
            break
        }

        if try await isGameRunning(runtime: runtime, diagnostics: diagnostics) {
            return .started
        }

        await progress(.game)
        try launchGameExecutable(game, runtime: runtime, diagnostics: diagnostics)
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

    static func gameEnvironment(base: [String: String], appID: String) -> [String: String] {
        var environment = base
        environment["SteamAppId"] = appID
        environment["SteamGameId"] = appID
        return environment
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
        diagnostics: Bool
    ) throws {
        let environment = Self.gameEnvironment(
            base: runtimeManager.environment(for: runtime, diagnostics: diagnostics),
            appID: descriptor.steamAppID
        )
        try processRunner.launch(
            executable: runtime.wineExecutable,
            arguments: runtime.wineArguments(for: [executable.path]),
            environment: environment,
            currentDirectory: executable.deletingLastPathComponent(),
            output: Self.interactiveOutput
        )
    }
}
