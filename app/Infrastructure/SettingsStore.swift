import Foundation

enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case borderlessFullscreen
    case exclusiveFullscreen
    case windowed
}

struct LauncherSettings: Codable, Equatable, Sendable {
    var displayMode = DisplayMode.borderlessFullscreen
    var width = 1920
    var height = 1080
    var verticalSync = true
    var fieldOfView = 95
    var enableDiagnostics = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case displayMode
        case launchInWindow
        case width
        case height
        case verticalSync
        case fieldOfView
        case enableDiagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let mode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) {
            displayMode = mode
        } else if try container.decodeIfPresent(Bool.self, forKey: .launchInWindow) == true {
            displayMode = .windowed
        }
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? width
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? height
        verticalSync = try container.decodeIfPresent(Bool.self, forKey: .verticalSync) ?? verticalSync
        fieldOfView = try container.decodeIfPresent(Int.self, forKey: .fieldOfView) ?? fieldOfView
        enableDiagnostics = try container.decodeIfPresent(Bool.self, forKey: .enableDiagnostics) ?? enableDiagnostics
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayMode, forKey: .displayMode)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(verticalSync, forKey: .verticalSync)
        try container.encode(fieldOfView, forKey: .fieldOfView)
        try container.encode(enableDiagnostics, forKey: .enableDiagnostics)
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
