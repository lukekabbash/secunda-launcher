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
        Runtime path: \(snapshot.runtimePath ?? "Unavailable")
        Bottle: \(snapshot.bottlePath)
        Steam: \(snapshot.steam.detail ?? "Unavailable")
        Skyrim: \(snapshot.gamePath ?? "Not installed")
        Saves: \(snapshot.saveCount)
        Backups: \(snapshot.backupCount)
        Free disk bytes: \(snapshot.freeDiskBytes)
        Logs: \(paths.logsDirectory.path)

        Secunda does not collect Steam credentials, session data, or personal documents.
        """
    }

    func latestLogExcerpt(maxCharacters: Int = 12_000) -> String {
        guard let logs = try? FileManager.default.contentsOfDirectory(
            at: paths.logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), let latest = logs.max(by: {
            let left = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let right = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (left ?? .distantPast) < (right ?? .distantPast)
        }), let contents = try? String(contentsOf: latest, encoding: .utf8)
        else {
            return "No runtime logs yet."
        }
        return String(contents.suffix(maxCharacters))
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
