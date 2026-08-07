import Foundation

/// Single source of truth for per-game constants. Supporting another game
/// means adding a descriptor here and giving it a library entry in the UI;
/// services read these fields instead of hardcoding one title.
struct GameDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let steamAppID: String
    let gameImageName: String
    let launcherImageName: String
    let documentsFolderName: String
    let defaultFieldOfView: Int

    static let skyrimSE = GameDescriptor(
        id: "skyrim-se",
        title: "Skyrim Special Edition",
        steamAppID: "489830",
        gameImageName: "SkyrimSE.exe",
        launcherImageName: "SkyrimSELauncher.exe",
        documentsFolderName: "Skyrim Special Edition",
        defaultFieldOfView: 80
    )

    static let supported: [GameDescriptor] = [.skyrimSE]
}
