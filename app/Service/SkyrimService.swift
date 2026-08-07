import Foundation

enum SkyrimLaunchOutcome: Equatable, Sendable {
    case started
    case alreadyRunning
}

enum SkyrimLaunchError: LocalizedError {
    case invalidInstallation
    case steamAuthorizationTimedOut
    case gameDidNotStart

    var errorDescription: String? {
        switch self {
        case .invalidInstallation:
            "Secunda could not safely resolve the installed Skyrim executable. Refresh or verify the game in Steam."
        case .steamAuthorizationTimedOut:
            "Steam did not make Skyrim ready in time. Leave Steam open, finish any sign-in or update, then press Play again."
        case .gameDidNotStart:
            "Steam authorized Skyrim, but the game did not stay running. Leave Steam open and try Play again."
        }
    }
}

final class SkyrimService {
    static let steamAppID = "489830"
    static let interactiveOutput: ProcessOutput = .discard

    private let paths: SecundaPaths
    private let steamService: SteamService
    private let bottleManager: BottleManager
    private let profileWriter: GameProfileWriter
    private let processRunner: ProcessRunner
    private let runtimeManager: RuntimeManager
    private let processProbe: WindowsProcessProbe

    init(
        paths: SecundaPaths,
        steamService: SteamService,
        bottleManager: BottleManager,
        processRunner: ProcessRunner,
        runtimeManager: RuntimeManager,
        processProbe: WindowsProcessProbe
    ) {
        self.paths = paths
        self.steamService = steamService
        self.bottleManager = bottleManager
        self.profileWriter = GameProfileWriter(paths: paths)
        self.processRunner = processRunner
        self.runtimeManager = runtimeManager
        self.processProbe = processProbe
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
        ).inspect(appID: Self.steamAppID, executableName: WindowsProcessProbe.gameImageName)
    }

    func launch(
        runtime: RuntimeDescriptor,
        settings: LauncherSettings,
        diagnostics: Bool,
        progress: @escaping (SkyrimLaunchStage) async -> Void = { _ in }
    ) async throws -> SkyrimLaunchOutcome {
        guard let game = validatedGameExecutable(in: runtime) else {
            throw SkyrimLaunchError.invalidInstallation
        }
        await progress(.checking)
        if try await isGameRunning(runtime: runtime, diagnostics: diagnostics) {
            return .alreadyRunning
        }

        await progress(.compatibility)
        try await bottleManager.applyGameCompatibility(runtime: runtime, diagnostics: diagnostics)
        await progress(.profile)
        try profileWriter.apply(settings, bottleRoot: runtime.bottleRoot)

        if try await isGameRunning(runtime: runtime, diagnostics: diagnostics) {
            return .alreadyRunning
        }

        await progress(.steam)
        try steamService.launch(
            runtime: runtime,
            arguments: ["-applaunch", Self.steamAppID],
            diagnostics: diagnostics
        )

        let handoff = try await processProbe.waitForHandoff(
            runtime: runtime,
            diagnostics: diagnostics,
            timeoutSeconds: 90
        )
        switch handoff {
        case .game:
            return .started
        case .none:
            throw SkyrimLaunchError.steamAuthorizationTimedOut
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
            timeoutSeconds: 20
        ) else {
            throw SkyrimLaunchError.gameDidNotStart
        }
        return .started
    }

    func requestVerification(runtime: RuntimeDescriptor, diagnostics: Bool) throws {
        try steamService.launch(
            runtime: runtime,
            arguments: ["steam://validate/\(Self.steamAppID)"],
            diagnostics: diagnostics
        )
    }

    static func gameEnvironment(base: [String: String]) -> [String: String] {
        var environment = base
        environment["SteamAppId"] = steamAppID
        environment["SteamGameId"] = steamAppID
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
        try await processProbe.snapshot(runtime: runtime, diagnostics: diagnostics)
            .contains(WindowsProcessProbe.gameImageName)
    }

    private func launchGameExecutable(
        _ executable: URL,
        runtime: RuntimeDescriptor,
        diagnostics: Bool
    ) throws {
        let environment = Self.gameEnvironment(
            base: runtimeManager.environment(for: runtime, diagnostics: diagnostics)
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
