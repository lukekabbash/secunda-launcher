import Foundation

struct LauncherSettings: Codable, Equatable, Sendable {
    var runtimeExecutablePath: String?
    var launchInWindow = false
    var width = 1920
    var height = 1080
    var enableDiagnostics = false
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
