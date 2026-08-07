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
        try FileManager.default.createDirectory(
            at: preferencesDirectory,
            withIntermediateDirectories: true
        )

        let profileURL = preferencesDirectory.appendingPathComponent("SkyrimPrefs.ini")
        let existingPrefs = (try? String(contentsOf: profileURL, encoding: .utf8)) ?? ""
        let updatedPrefs = Self.updatingDisplaySection(in: existingPrefs, settings: settings)
        try updatedPrefs.write(to: profileURL, atomically: true, encoding: .utf8)

        // FOV lives in SkyrimCustom.ini, which the game reads as an override
        // of Skyrim.ini; the launcher never rewrites it, unlike SkyrimPrefs.ini.
        let customURL = preferencesDirectory.appendingPathComponent("SkyrimCustom.ini")
        let existingCustom = (try? String(contentsOf: customURL, encoding: .utf8)) ?? ""
        let updatedCustom = Self.updatingCustomDisplaySection(in: existingCustom, settings: settings)
        try updatedCustom.write(to: customURL, atomically: true, encoding: .utf8)
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
        return mergingDisplayValues(values, into: contents)
    }

    static func updatingCustomDisplaySection(
        in contents: String,
        settings: LauncherSettings
    ) -> String {
        let fov = String(settings.fieldOfView)
        return mergingDisplayValues(
            [
                "fDefault1stPersonFOV": fov,
                "fDefaultWorldFOV": fov
            ],
            into: contents
        )
    }

    private static func mergingDisplayValues(
        _ values: [String: String],
        into contents: String
    ) -> String {
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
            .appendingPathComponent(
                "Documents/My Games/\(GameDescriptor.skyrimSE.documentsFolderName)",
                isDirectory: true
            )
    }
}
