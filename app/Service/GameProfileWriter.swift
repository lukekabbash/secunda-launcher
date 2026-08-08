import Foundation

struct GameProfileWriter {
    /// The bottle's standard Windows DPI. Chosen so Steam's interface is
    /// legible on Retina panels; DPI-unaware game windows are scaled by
    /// LogPixels/96 (2.25x) under it.
    static let standardLogPixels = 216
    static let nativeLogPixels = 96

    private let paths: SecundaPaths
    private let descriptor: GameDescriptor

    init(paths: SecundaPaths, descriptor: GameDescriptor) {
        self.paths = paths
        self.descriptor = descriptor
    }

    /// DPI-unaware game windows are virtualized by LogPixels/96 (2.25x at the
    /// standard DPI). Keep the standard DPI only while that scaled footprint
    /// still fits the panel; otherwise map the session 1:1 to physical pixels
    /// so large and native resolutions fit the screen sharp instead of
    /// overflowing it. Titles that prefer native session DPI always get 96 so
    /// mouse look deltas aren't quantized by Retina virtualization.
    static func sessionLogPixels(
        settings: GameSettings,
        screenPixelWidth: Int,
        prefersNative: Bool = false
    ) -> Int {
        if prefersNative { return nativeLogPixels }
        guard screenPixelWidth > 0 else { return standardLogPixels }
        let scaledWidth = settings.width * standardLogPixels / nativeLogPixels
        return scaledWidth > screenPixelWidth ? nativeLogPixels : standardLogPixels
    }

    /// Metal-paced borderless sessions write bMaximizeWindow=1, so the
    /// engine sizes its window to the whole desktop — at native session DPI
    /// that's the full physical panel. The UI anchors against iSize W/H, so
    /// a smaller stored resolution draws the menus offset from the window.
    /// Render at the panel size the maximized window actually gets.
    static func sessionSettings(
        _ settings: GameSettings,
        descriptor: GameDescriptor,
        logPixels: Int,
        screenPixelWidth: Int,
        screenPixelHeight: Int
    ) -> GameSettings {
        guard logPixels == nativeLogPixels,
              descriptor.usesMetalFramePacing,
              settings.displayMode == .borderlessFullscreen,
              screenPixelWidth > 0,
              screenPixelHeight > 0
        else { return settings }
        var adjusted = settings
        adjusted.width = screenPixelWidth
        adjusted.height = screenPixelHeight
        return adjusted
    }

    func apply(_ settings: GameSettings, bottleRoot: URL) throws {
        // Games without any Secunda-writable profile manage settings
        // themselves; nothing to write.
        let writesLuaPrefs = descriptor.luaPrefsRelativePath != nil && !descriptor.luaTuningOptions.isEmpty
        let writesCustomIni = descriptor.customIniFileName != nil
            && (descriptor.supportsDisplayProfile || !descriptor.customIniValues.isEmpty)
        guard descriptor.supportsDisplayProfile || writesLuaPrefs || writesCustomIni else { return }
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

        if let prefsFileName = descriptor.prefsFileName {
            let profileURL = preferencesDirectory.appendingPathComponent(prefsFileName)
            let existingPrefs = (try? String(contentsOf: profileURL, encoding: .utf8)) ?? ""
            var updatedPrefs = Self.updatingDisplaySection(
                in: existingPrefs,
                settings: settings,
                vsyncKey: descriptor.vsyncKey,
                usesMetalFramePacing: descriptor.usesMetalFramePacing
            )
            let qualityValues = Self.qualityValues(settings: settings, descriptor: descriptor)
            if !qualityValues.isEmpty {
                updatedPrefs = Self.mergingDisplayValues(qualityValues, into: updatedPrefs)
            }
            try updatedPrefs.write(to: profileURL, atomically: true, encoding: .utf8)
        }

        // FOV and per-game Custom.ini overrides live here — the engine reads
        // them as overrides and the vendor launcher never rewrites them.
        if let customIniFileName = descriptor.customIniFileName {
            let customURL = preferencesDirectory.appendingPathComponent(customIniFileName)
            let existingCustom = (try? String(contentsOf: customURL, encoding: .utf8)) ?? ""
            var updatedCustom = existingCustom
            if descriptor.supportsDisplayProfile {
                updatedCustom = Self.updatingCustomDisplaySection(
                    in: updatedCustom,
                    settings: settings
                )
            }
            updatedCustom = Self.mergingCustomIniValues(
                Self.resolvedCustomIniValues(settings: settings, descriptor: descriptor),
                into: updatedCustom
            )
            if updatedCustom != existingCustom {
                try updatedCustom.write(to: customURL, atomically: true, encoding: .utf8)
            }
        }

        // Lua-style prefs (Game.prefs): rewrite only keys the game itself
        // has already written — never invent structure. Absent file or
        // absent keys are silently skipped, so a launch can't fail here.
        if writesLuaPrefs, let luaRelativePath = descriptor.luaPrefsRelativePath {
            let luaURL = paths.activeWindowsUserDirectory(in: bottleRoot)
                .appendingPathComponent(luaRelativePath)
            guard paths.contains(luaURL, inBottleRoot: bottleRoot),
                  let existing = try? String(contentsOf: luaURL, encoding: .utf8)
            else { return }
            var updated = existing
            for option in descriptor.luaTuningOptions {
                guard let chosenLabel = settings.tuning[option.id],
                      let choice = option.choices.first(where: { $0.label == chosenLabel }),
                      !choice.value.isEmpty
                else { continue }
                updated = Self.updatingLuaNumericValue(
                    in: updated,
                    keyCandidates: option.keyCandidates,
                    value: choice.value
                )
            }
            if updated != existing {
                try updated.write(to: luaURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Replace `key = <number>` (and quoted `key = '<number>'` / `key = "<number>"`)
    /// for the first candidate key present, everywhere it occurs. Returns the
    /// input unchanged when no candidate matches.
    static func updatingLuaNumericValue(
        in contents: String,
        keyCandidates: [String],
        value: String
    ) -> String {
        for key in keyCandidates {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let pattern = "(\\b\(escaped)\\b\\s*=\\s*)(['\"]?)[0-9]+(['\"]?)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(contents.startIndex..., in: contents)
            guard regex.firstMatch(in: contents, range: range) != nil else { continue }
            return regex.stringByReplacingMatches(
                in: contents,
                range: range,
                withTemplate: "$1$2\(value)$3"
            )
        }
        return contents
    }

    static func updatingDisplaySection(
        in contents: String,
        settings: GameSettings,
        vsyncKey: String = "iVSyncPresentInterval",
        usesMetalFramePacing: Bool = false
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
        // Metal present pacing already locks the frame rate. Leaving the
        // game's vsync interval on stacks a second wait and feels sticky.
        let vsyncValue = usesMetalFramePacing ? "0" : (settings.verticalSync ? "1" : "0")
        var values = [
            "bBorderless": borderless,
            "bFull Screen": fullscreen,
            "iSize H": String(settings.height),
            "iSize W": String(settings.width),
            vsyncKey: vsyncValue
        ]
        if usesMetalFramePacing, settings.displayMode == .borderlessFullscreen {
            values["bMaximizeWindow"] = "1"
        }
        return mergingDisplayValues(values, into: contents)
    }

    static func updatingCustomDisplaySection(
        in contents: String,
        settings: GameSettings
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

    /// Descriptor Custom.ini maps plus resolution-dependent look scales.
    static func resolvedCustomIniValues(
        settings: GameSettings,
        descriptor: GameDescriptor
    ) -> [String: [String: String]] {
        var sections = descriptor.customIniValues
        guard descriptor.appliesAspectCorrectMouseLook, settings.height > 0 else {
            return sections
        }
        var controls = sections["Controls"] ?? [:]
        controls["bMouseAcceleration"] = "0"
        controls["bBackgroundMouse"] = "1"
        controls["fMouseHeadingXScale"] = "0.021"
        // Engine default halves vertical look vs horizontal; scale Y by aspect.
        let yScale = 0.021 * Double(settings.width) / Double(settings.height)
        controls["fMouseHeadingYScale"] = String(format: "%.5f", yScale)
        sections["Controls"] = controls
        return sections
    }

    /// Apply descriptor-owned Custom.ini section maps in stable section order.
    static func mergingCustomIniValues(
        _ sections: [String: [String: String]],
        into contents: String
    ) -> String {
        var updated = contents
        for section in sections.keys.sorted() {
            guard let values = sections[section], !values.isEmpty else { continue }
            updated = mergingSectionValues(values, into: updated, section: section)
        }
        return updated
    }

    /// Resolve the player's chosen quality options into concrete ini keys.
    /// Unknown option ids or labels resolve to nothing, so stale stored
    /// choices can never write garbage.
    static func qualityValues(
        settings: GameSettings,
        descriptor: GameDescriptor
    ) -> [String: String] {
        var values: [String: String] = [:]
        for (optionID, chosenLabel) in settings.quality {
            guard let option = descriptor.qualityOption(for: optionID),
                  let choice = option.choices.first(where: { $0.label == chosenLabel })
            else { continue }
            values.merge(choice.values) { _, new in new }
        }
        return values
    }

    static func mergingDisplayValues(
        _ values: [String: String],
        into contents: String
    ) -> String {
        mergingSectionValues(values, into: contents, section: "Display")
    }

    static func mergingSectionValues(
        _ values: [String: String],
        into contents: String,
        section: String
    ) -> String {
        let heading = "[\(section)]"
        var lines = contents.components(separatedBy: .newlines)
        if lines.last == "" { lines.removeLast() }

        guard let sectionStart = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(heading) == .orderedSame
        }) else {
            if !lines.isEmpty { lines.append("") }
            lines.append(heading)
            lines.append(contentsOf: values.keys.sorted().map { "\($0)=\(values[$0]!)" })
            return lines.joined(separator: "\r\n") + "\r\n"
        }

        var sectionEnd = lines[(sectionStart + 1)..<lines.endIndex].firstIndex(where: {
            let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.hasPrefix("[") && line.hasSuffix("]")
        }) ?? lines.endIndex

        for key in values.keys.sorted() {
            let range = (sectionStart + 1)..<sectionEnd
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
                "Documents/\(descriptor.documentsRelativePath)",
                isDirectory: true
            )
    }
}
