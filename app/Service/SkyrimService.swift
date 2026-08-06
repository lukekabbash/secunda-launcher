import Foundation

final class SkyrimService {
    static let steamAppID = "489830"

    private let paths: SecundaPaths
    private let steamService: SteamService
    private let bottleManager: BottleManager
    private let profileWriter: GameProfileWriter

    init(paths: SecundaPaths, steamService: SteamService, bottleManager: BottleManager) {
        self.paths = paths
        self.steamService = steamService
        self.bottleManager = bottleManager
        self.profileWriter = GameProfileWriter(paths: paths)
    }

    func executable(in runtime: RuntimeDescriptor?) -> URL? {
        let libraryRoots = steamLibraryRoots(runtime: runtime)
        let candidates = libraryRoots.map {
            $0.appendingPathComponent("steamapps/common/Skyrim Special Edition/SkyrimSE.exe")
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func launch(
        runtime: RuntimeDescriptor,
        settings: LauncherSettings,
        diagnostics: Bool
    ) async throws {
        try await bottleManager.applyGameCompatibility(runtime: runtime, diagnostics: diagnostics)
        try profileWriter.apply(settings, bottleRoot: runtime.bottleRoot)
        try steamService.launch(
            runtime: runtime,
            arguments: ["-applaunch", Self.steamAppID],
            diagnostics: diagnostics
        )
    }

    func requestVerification(runtime: RuntimeDescriptor, diagnostics: Bool) throws {
        try steamService.launch(
            runtime: runtime,
            arguments: ["steam://validate/\(Self.steamAppID)"],
            diagnostics: diagnostics
        )
    }

    private func steamLibraryRoots(runtime: RuntimeDescriptor?) -> [URL] {
        var roots: [URL] = []
        if let steam = steamService.executable(in: runtime) {
            roots.append(steam.deletingLastPathComponent())
        }

        return roots
    }
}
