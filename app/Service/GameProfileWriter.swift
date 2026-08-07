import Foundation

struct GameProfileWriter {
    private let paths: SecundaPaths

    init(paths: SecundaPaths) {
        self.paths = paths
    }

    func apply(_ settings: LauncherSettings, bottleRoot: URL) throws {
        guard BottleManager.hasPrivateDocuments(paths: paths, bottleRoot: bottleRoot) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let preferencesDirectory = preferencesDirectory(in: bottleRoot)
        guard paths.contains(preferencesDirectory, inBottleRoot: bottleRoot) else {
            throw CocoaError(.fileWriteNoPermission)
        }
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
        // Borderless windowed is the default: exclusive fullscreen through
        // Wine's Mac driver cannot reliably regain the display after Cmd-Tab.
        let fullscreen: String
        let borderless: String
        switch settings.displayMode {
        case .borderlessFullscreen:
            fullscreen = "0"
            borderless = "1"
        case .exclusiveFullscreen:
            fullscreen = "1"
            borderless = "0"
        case .windowed:
            fullscreen = "0"
            borderless = "0"
        }
        let values = [
            "bBorderless": borderless,
            "bFull Screen": fullscreen,
            "iSize H": String(settings.height),
            "iSize W": String(settings.width),
            "iVSyncPresentInterval": settings.verticalSync ? "1" : "0"
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
