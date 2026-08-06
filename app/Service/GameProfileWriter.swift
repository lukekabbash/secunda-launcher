import Foundation

struct GameProfileWriter {
    private let paths: SecundaPaths

    init(paths: SecundaPaths) {
        self.paths = paths
    }

    func apply(_ settings: LauncherSettings, bottleRoot: URL) throws {
        let preferencesDirectory = preferencesDirectory(in: bottleRoot)
        let profileURL = preferencesDirectory.appendingPathComponent("SkyrimPrefs.ini")
        let existing = (try? String(contentsOf: profileURL, encoding: .utf8)) ?? ""
        let updated = Self.updatingDisplaySection(in: existing, settings: settings)

        try FileManager.default.createDirectory(
            at: preferencesDirectory,
            withIntermediateDirectories: true
        )
        try updated.write(to: profileURL, atomically: true, encoding: .utf8)
    }

    static func updatingDisplaySection(
        in contents: String,
        settings: LauncherSettings
    ) -> String {
        let fullscreen = settings.launchInWindow ? "0" : "1"
        let borderless = settings.launchInWindow ? "0" : "1"
        let values = [
            "bBorderless": borderless,
            "bFull Screen": fullscreen,
            "iSize H": String(settings.height),
            "iSize W": String(settings.width)
        ]

        var lines = contents.components(separatedBy: .newlines)
        if lines.last == "" { lines.removeLast() }

        guard let displayStart = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("[Display]") == .orderedSame
        }) else {
            if !lines.isEmpty { lines.append("") }
            lines.append("[Display]")
            lines.append(contentsOf: values.keys.sorted().map { "\($0)=\(values[$0]!)" })
            return lines.joined(separator: "\r\n") + "\r\n"
        }

        var sectionEnd = lines[(displayStart + 1)..<lines.endIndex].firstIndex(where: {
            let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.hasPrefix("[") && line.hasSuffix("]")
        }) ?? lines.endIndex

        for key in values.keys.sorted() {
            let range = (displayStart + 1)..<sectionEnd
            if let index = lines[range].firstIndex(where: {
                $0.split(separator: "=", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(key) == .orderedSame
            }) {
                lines[index] = "\(key)=\(values[key]!)"
            } else {
                lines.insert("\(key)=\(values[key]!)", at: sectionEnd)
                sectionEnd += 1
            }
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private func preferencesDirectory(in bottleRoot: URL) -> URL {
        paths.activeWindowsUserDirectory(in: bottleRoot)
            .appendingPathComponent("Documents/My Games/Skyrim Special Edition", isDirectory: true)
    }
}
