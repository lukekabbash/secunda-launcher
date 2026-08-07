import Foundation

final class DiagnosticService {
    private let paths: SecundaPaths

    init(paths: SecundaPaths) {
        self.paths = paths
    }

    func report(snapshot: LauncherSnapshot) -> String {
        let process = ProcessInfo.processInfo
        return """
        Secunda Launcher Diagnostics
        Generated: \(ISO8601DateFormatter().string(from: Date()))

        macOS: \(process.operatingSystemVersionString)
        Architecture: \(Self.architecture)
        Runtime: \(snapshot.runtime.detail ?? "Unavailable")
        Runtime path: \(redacted(snapshot.runtimePath))
        Managed game space: \(redacted(snapshot.bottlePath))
        Steam: \(snapshot.steam.detail ?? "Unavailable")
        \(gameLines(snapshot: snapshot))
        Free disk bytes: \(snapshot.freeDiskBytes)
        Logs: \(redacted(paths.logsDirectory.path))

        Secunda does not collect Steam credentials, session data, or personal documents.
        """
    }

    private func gameLines(snapshot: LauncherSnapshot) -> String {
        GameDescriptor.supported.map { descriptor in
            let game = snapshot.game(descriptor)
            return """
            \(descriptor.shortTitle): \(redacted(game.path, fallback: "Not installed"))
            \(descriptor.shortTitle) saves: \(game.saveCount) (backups: \(game.backupCount))
            """
        }.joined(separator: "\n")
    }

    private func redacted(_ path: String?, fallback: String = "Unavailable") -> String {
        guard let path else { return fallback }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    func latestLogExcerpt(maxCharacters: Int = 12_000) -> String {
        guard let logs = try? FileManager.default.contentsOfDirectory(
            at: paths.logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "No runtime logs yet."
        }
        let safeLogs = logs.filter { Self.isSafeSupportLog($0) }
        guard let latest = safeLogs.max(by: {
            let left = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let right = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (left ?? .distantPast) < (right ?? .distantPast)
        }), let contents = try? String(contentsOf: latest, encoding: .utf8)
        else {
            return "No runtime logs yet."
        }
        return String(contents.suffix(maxCharacters))
    }

    static func isSafeSupportLog(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name != "steam-launch.log"
            && !name.contains("interactive-launch")
            && !name.contains("game-launch")
    }

    private static var architecture: String {
        #if arch(arm64)
        "Apple silicon (arm64)"
        #elseif arch(x86_64)
        "Intel (x86_64)"
        #else
        "Unknown"
        #endif
    }
}
