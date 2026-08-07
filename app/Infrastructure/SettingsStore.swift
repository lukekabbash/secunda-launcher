import Foundation

enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case borderlessFullscreen
    case exclusiveFullscreen
    case windowed
}

/// Display and audio choices for one game. Stored per game so every title
/// in the library keeps its own profile.
struct GameSettings: Codable, Equatable, Sendable {
    var displayMode = DisplayMode.borderlessFullscreen
    var width = 1920
    var height = 1080
    var verticalSync = true
    var fieldOfView = 95
    var nativeVoiceAudio = true
    /// Chosen quality options, keyed by QualityOption id → choice label.
    /// Absent entries mean "Game default" (write nothing).
    var quality: [String: String] = [:]
    /// Chosen Lua-prefs tuning, keyed by LuaTuningOption id → choice label.
    var tuning: [String: String] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case displayMode
        case width
        case height
        case verticalSync
        case fieldOfView
        case nativeVoiceAudio
        case quality
        case tuning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? displayMode
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? width
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? height
        verticalSync = try container.decodeIfPresent(Bool.self, forKey: .verticalSync) ?? verticalSync
        fieldOfView = try container.decodeIfPresent(Int.self, forKey: .fieldOfView) ?? fieldOfView
        nativeVoiceAudio = try container.decodeIfPresent(Bool.self, forKey: .nativeVoiceAudio) ?? nativeVoiceAudio
        quality = try container.decodeIfPresent([String: String].self, forKey: .quality) ?? quality
        tuning = try container.decodeIfPresent([String: String].self, forKey: .tuning) ?? tuning
    }
}

struct LauncherSettings: Codable, Equatable, Sendable {
    var enableDiagnostics = false
    var games: [String: GameSettings] = [:]

    init() {}

    /// Settings for one game, falling back to defaults for games that have
    /// never been configured.
    func game(_ descriptor: GameDescriptor) -> GameSettings {
        games[descriptor.id] ?? GameSettings()
    }

    mutating func setGame(_ settings: GameSettings, for descriptor: GameDescriptor) {
        games[descriptor.id] = settings
    }

    private enum CodingKeys: String, CodingKey {
        case enableDiagnostics
        case games
        // Legacy flat keys from the single-game settings file.
        case displayMode
        case launchInWindow
        case width
        case height
        case verticalSync
        case fieldOfView
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableDiagnostics = try container.decodeIfPresent(Bool.self, forKey: .enableDiagnostics) ?? false
        if let games = try container.decodeIfPresent([String: GameSettings].self, forKey: .games) {
            self.games = games
            return
        }

        // Migrate the legacy flat file into Skyrim's per-game entry.
        var legacy = GameSettings()
        if let mode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) {
            legacy.displayMode = mode
        } else if try container.decodeIfPresent(Bool.self, forKey: .launchInWindow) == true {
            legacy.displayMode = .windowed
        }
        legacy.width = try container.decodeIfPresent(Int.self, forKey: .width) ?? legacy.width
        legacy.height = try container.decodeIfPresent(Int.self, forKey: .height) ?? legacy.height
        legacy.verticalSync = try container.decodeIfPresent(Bool.self, forKey: .verticalSync) ?? legacy.verticalSync
        legacy.fieldOfView = try container.decodeIfPresent(Int.self, forKey: .fieldOfView) ?? legacy.fieldOfView
        games = [GameDescriptor.skyrimSE.id: legacy]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enableDiagnostics, forKey: .enableDiagnostics)
        try container.encode(games, forKey: .games)
    }
}

final class SettingsStore {
    private let paths: SecundaPaths
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(paths: SecundaPaths) {
        self.paths = paths
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> LauncherSettings {
        guard let data = try? Data(contentsOf: paths.settingsFile),
              let settings = try? decoder.decode(LauncherSettings.self, from: data)
        else {
            return LauncherSettings()
        }
        return settings
    }

    func save(_ settings: LauncherSettings) throws {
        try paths.prepareManagedDirectories()
        let data = try encoder.encode(settings)
        try data.write(to: paths.settingsFile, options: .atomic)
    }
}
