import Foundation

/// One optional add-on for a supported game. Detection is by file presence
/// inside the installed game directory; installation is always performed by
/// Steam itself for add-ons that have their own Steam app identifier.
struct DLCDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let steamAppID: String?
    let detectionFile: String
    let note: String?

    init(
        id: String,
        title: String,
        steamAppID: String? = nil,
        detectionFile: String,
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.steamAppID = steamAppID
        self.detectionFile = detectionFile
        self.note = note
    }
}

/// Single source of truth for per-game constants. Supporting another game
/// means adding a descriptor here and registering it in `supported`;
/// services read these fields instead of hardcoding one title.
struct GameDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let shortTitle: String
    let tagline: String
    let symbol: String
    let steamAppID: String
    let gameImageName: String
    let launcherImageName: String
    let documentsFolderName: String
    let prefsFileName: String
    let customIniFileName: String
    let saveFileExtensions: [String]
    let defaultFieldOfView: Int
    let dlc: [DLCDescriptor]

    /// Steam's own artwork CDN. Fetched at runtime for the player's library
    /// presentation and never redistributed inside Secunda.
    var cardArtworkURL: URL? {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(steamAppID)/library_600x900.jpg")
    }

    var heroArtworkURL: URL? {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(steamAppID)/library_hero.jpg")
    }

    var logoArtworkURL: URL? {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(steamAppID)/logo.png")
    }

    static let skyrimSE = GameDescriptor(
        id: "skyrim-se",
        title: "The Elder Scrolls V: Skyrim Special Edition",
        shortTitle: "Skyrim",
        tagline: "Dragons, shouts, and a province that never lets go.",
        symbol: "mountain.2.fill",
        steamAppID: "489830",
        gameImageName: "SkyrimSE.exe",
        launcherImageName: "SkyrimSELauncher.exe",
        documentsFolderName: "Skyrim Special Edition",
        prefsFileName: "SkyrimPrefs.ini",
        customIniFileName: "SkyrimCustom.ini",
        saveFileExtensions: ["ess"],
        defaultFieldOfView: 80,
        dlc: [
            DLCDescriptor(
                id: "skyrim-dawnguard",
                title: "Dawnguard",
                detectionFile: "Data/Dawnguard.esm",
                note: "Included with Special Edition."
            ),
            DLCDescriptor(
                id: "skyrim-hearthfire",
                title: "Hearthfire",
                detectionFile: "Data/HearthFires.esm",
                note: "Included with Special Edition."
            ),
            DLCDescriptor(
                id: "skyrim-dragonborn",
                title: "Dragonborn",
                detectionFile: "Data/Dragonborn.esm",
                note: "Included with Special Edition."
            ),
            DLCDescriptor(
                id: "skyrim-anniversary",
                title: "Anniversary Upgrade",
                steamAppID: "1746860",
                detectionFile: "Data/ccBGSSSE001-Fish.esm",
                note: "Paid upgrade adding all Creation Club content."
            )
        ]
    )

    static let fallout4 = GameDescriptor(
        id: "fallout-4",
        title: "Fallout 4",
        shortTitle: "Fallout 4",
        tagline: "War never changes. The Commonwealth is waiting.",
        symbol: "atom",
        steamAppID: "377160",
        gameImageName: "Fallout4.exe",
        launcherImageName: "Fallout4Launcher.exe",
        documentsFolderName: "Fallout4",
        prefsFileName: "Fallout4Prefs.ini",
        customIniFileName: "Fallout4Custom.ini",
        saveFileExtensions: ["fos"],
        defaultFieldOfView: 80,
        dlc: [
            DLCDescriptor(
                id: "fallout4-automatron",
                title: "Automatron",
                steamAppID: "435880",
                detectionFile: "Data/DLCRobot.esm"
            ),
            DLCDescriptor(
                id: "fallout4-wasteland-workshop",
                title: "Wasteland Workshop",
                steamAppID: "435881",
                detectionFile: "Data/DLCworkshop01.esm"
            ),
            DLCDescriptor(
                id: "fallout4-far-harbor",
                title: "Far Harbor",
                steamAppID: "435870",
                detectionFile: "Data/DLCCoast.esm"
            ),
            DLCDescriptor(
                id: "fallout4-contraptions",
                title: "Contraptions Workshop",
                steamAppID: "480630",
                detectionFile: "Data/DLCworkshop02.esm"
            ),
            DLCDescriptor(
                id: "fallout4-vault-tec",
                title: "Vault-Tec Workshop",
                steamAppID: "480631",
                detectionFile: "Data/DLCworkshop03.esm"
            ),
            DLCDescriptor(
                id: "fallout4-nuka-world",
                title: "Nuka-World",
                steamAppID: "490650",
                detectionFile: "Data/DLCNukaWorld.esm"
            ),
            DLCDescriptor(
                id: "fallout4-hd-textures",
                title: "High Resolution Texture Pack",
                steamAppID: "540810",
                detectionFile: "Data/DLCUltraHighResolution - Textures01.ba2",
                note: "Free but ~58 GB and heavy on the GPU. Not recommended on this runtime."
            )
        ]
    )

    static let supported: [GameDescriptor] = [.skyrimSE, .fallout4]

    static func descriptor(for id: String) -> GameDescriptor? {
        supported.first { $0.id == id }
    }
}
