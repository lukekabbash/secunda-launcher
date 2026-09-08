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

        Version: \(AppVersion.label)
        Diagnostic source: \(Self.diagnosticSourceCommit)
        macOS: \(process.operatingSystemVersionString)
        Architecture: \(Self.architecture)
        Physical memory bytes: \(process.physicalMemory)
        Runtime: \(snapshot.runtime.detail ?? "Unavailable")
        Runtime path: \(redacted(snapshot.runtimePath))
        Managed game space: \(redacted(snapshot.bottlePath))
        Steam: \(snapshot.steam.detail ?? "Unavailable")
        \(gameLines(snapshot: snapshot))
        Free disk bytes: \(snapshot.freeDiskBytes)
        Logs: \(redacted(paths.logsDirectory.path))
        Launch timeline: \(GameLaunchRecorder.fileName)

        Secunda does not collect Steam credentials, session data, personal documents, window titles, or captured image pixels in its normal support timeline.
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

    /// Prefer the latest attempt-linked privacy-safe timeline over whichever
    /// bootstrap/probe file happened to be modified last. Raw Steam and game
    /// launch logs stay excluded from the UI support excerpt.
    func latestLogExcerpt(maxCharacters: Int = 12_000) -> String {
        if let timeline = latestAttemptTimeline(maxCharacters: maxCharacters) {
            return timeline
        }

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
        return "Latest safe runtime log: \(latest.lastPathComponent)\n\n"
            + String(contents.suffix(maxCharacters))
    }

    private func latestAttemptTimeline(maxCharacters: Int) -> String? {
        let candidates = [
            paths.logsDirectory.appendingPathComponent(GameLaunchRecorder.fileName),
            paths.logsDirectory.appendingPathComponent(GameLaunchRecorder.archiveFileName)
        ]
        let readable = candidates.compactMap { url -> (URL, String, Date)? in
            guard let contents = try? String(contentsOf: url, encoding: .utf8),
                  !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (url, contents, modified)
        }
        guard let newest = readable.max(by: { $0.2 < $1.2 }) else { return nil }

        let lines = newest.1.split(whereSeparator: \.isNewline).map(String.init)
        guard let lastAttemptID = lines.reversed().compactMap(Self.attemptID(in:)).first else {
            return "Latest launch timeline: \(newest.0.lastPathComponent)\n\n"
                + String(newest.1.suffix(maxCharacters))
        }
        let matching = lines.filter { Self.attemptID(in: $0) == lastAttemptID }
        let body = matching.joined(separator: "\n")
        return "Latest launch attempt: \(lastAttemptID)\n"
            + "Source: \(newest.0.lastPathComponent)\n\n"
            + String(body.suffix(maxCharacters))
    }

    private static func attemptID(in line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let attemptID = object["attemptID"] as? String,
              !attemptID.isEmpty
        else { return nil }
        return attemptID
    }

    static func isSafeSupportLog(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name != "steam-launch.log"
            && !name.contains("interactive-launch")
            && !name.contains("game-launch")
    }

    private static var diagnosticSourceCommit: String {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "SecundaDiagnosticSourceCommit"
        ) as? String, !value.isEmpty else {
            return "Not embedded"
        }
        return String(value.prefix(64))
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
