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
    /// mouse look deltas aren't quantized by Retina virtualization. Titles
    /// whose resolution is game-owned keep the bottle's standard DPI instead
    /// of deriving presentation from stale launcher settings.
    static func sessionLogPixels(
        settings: GameSettings,
        screenPixelWidth: Int,
        prefersNative: Bool = false,
        managesResolution: Bool = true
    ) -> Int {
        if prefersNative { return nativeLogPixels }
        guard managesResolution else { return standardLogPixels }
        guard screenPixelWidth > 0 else { return standardLogPixels }
        let scaledWidth = settings.width * standardLogPixels / nativeLogPixels
        return scaledWidth > screenPixelWidth ? nativeLogPixels : standardLogPixels
    }

    /// Screen-covering borderless native-DPI sessions use the full display
    /// point size. Captured exclusive sessions keep the validated switchable
    /// mode selected by the player.
    static func sessionSettings(
        _ settings: GameSettings,
        descriptor: GameDescriptor,
        logPixels: Int,
        screenPointWidth: Int,
        screenPointHeight: Int,
        preservesRequestedResolution: Bool = false
    ) -> GameSettings {
        guard !preservesRequestedResolution,
              logPixels == nativeLogPixels,
              descriptor.prefersNativeSessionDPI,
              screenPointWidth > 0,
              screenPointHeight > 0
        else { return settings }
        let usesFullDisplay = settings.displayMode == .borderlessFullscreen
            && descriptor.usesScreenCoveringBorderlessSurface
        guard usesFullDisplay else { return settings }
        var adjusted = settings
        adjusted.width = screenPointWidth
        adjusted.height = screenPointHeight
        return adjusted
    }

    func apply(
        _ settings: GameSettings,
        bottleRoot: URL,
        installRoot: URL? = nil
    ) throws {
        // Games without any Secunda-writable profile manage settings
        // themselves; nothing to write.
        let writesLuaPrefs = descriptor.luaPrefsRelativePath != nil
            && (!descriptor.luaTuningOptions.isEmpty
                || !descriptor.luaPrefsAdapterKeyCandidates.isEmpty
                || descriptor.managesLuaDesktopWindow)
        let writesCustomIni = descriptor.customIniFileName != nil
            && (descriptor.supportsDisplayProfile || !descriptor.customIniValues.isEmpty)
        let writesManagedINI = !descriptor.managedINIProfiles.isEmpty
        guard descriptor.supportsDisplayProfile
                || writesLuaPrefs
                || writesCustomIni
                || writesManagedINI
        else { return }

        if descriptor.supportsDisplayProfile || writesCustomIni {
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
                if updatedPrefs != existingPrefs {
                    try updatedPrefs.write(to: profileURL, atomically: true, encoding: .utf8)
                }
            }

            // FOV and per-game Custom.ini overrides live here — the engine
            // reads them as overrides and the vendor launcher never rewrites them.
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
        }

        // Lua-style prefs (Game.prefs): rewrite only keys the game itself
        // has already written — never invent structure. Absent file or
        // absent keys are silently skipped, so a launch can't fail here.
        if writesLuaPrefs, let luaRelativePath = descriptor.luaPrefsRelativePath {
            let luaURL = paths.activeWindowsUserDirectory(in: bottleRoot)
                .appendingPathComponent(luaRelativePath)
            if paths.contains(luaURL, inBottleRoot: bottleRoot),
               let existing = try? String(contentsOf: luaURL, encoding: .utf8) {
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
                if !descriptor.luaPrefsAdapterKeyCandidates.isEmpty {
                    updated = Self.updatingLuaAdapterValue(
                        in: updated,
                        keyCandidates: descriptor.luaPrefsAdapterKeyCandidates,
                        width: settings.width,
                        height: settings.height
                    )
                }
                if descriptor.managesLuaDesktopWindow {
                    updated = Self.updatingLuaNumericValue(
                        in: updated,
                        keyCandidates: ["lock_fullscreen_cursor_to_window"],
                        value: settings.displayMode == .windowed ? "0" : "1"
                    )
                    if settings.displayMode != .windowed {
                        updated = Self.updatingLuaTableNumericValues(
                            in: updated,
                            tablePath: ["Windows", "Main"],
                            values: ["x": "0", "y": "0"]
                        )
                    }
                }
                if updated != existing {
                    try updated.write(to: luaURL, atomically: true, encoding: .utf8)
                }
            }
        }

        if writesManagedINI, let installRoot {
            try applyManagedINIProfiles(
                settings,
                installRoot: installRoot
            )
        }
    }

    private func applyManagedINIProfiles(
        _ settings: GameSettings,
        installRoot: URL
    ) throws {
        let root = installRoot.standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let quality = Self.qualityValues(settings: settings, descriptor: descriptor)
        for profile in descriptor.managedINIProfiles {
            let components = profile.relativePath.split(separator: "/").map(String.init)
            guard !profile.relativePath.hasPrefix("/"),
                  !components.isEmpty,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  components.last?.lowercased().hasPrefix("default") == false
            else { continue }
            let target = components.reduce(root) { partial, component in
                partial.appendingPathComponent(component)
            }.standardizedFileURL
            guard target.path.hasPrefix(root.path + "/"),
                  target.resolvingSymlinksInPath().standardizedFileURL.path
                    .hasPrefix(resolvedRoot.path + "/"),
                  let values = try? target.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                  ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: target),
                  let contents = String(data: data, encoding: .utf8),
                  !contents.contains("\0")
            else { continue }

            var replacements = Self.managedINIValues(
                profile: profile,
                settings: settings
            )
            if profile.includesQualityValues {
                replacements.merge(quality) { _, selected in selected }
            }
            let updated: String
            switch profile.format {
            case .sectionedINI:
                updated = Self.mergingExistingSectionValues(
                    replacements,
                    into: contents,
                    section: profile.section
                )
            case .quotedKeyValues:
                updated = Self.mergingExistingQuotedKeyValues(
                    replacements,
                    into: contents
                )
            }
            if updated != contents {
                try updated.write(to: target, atomically: true, encoding: .utf8)
            }
        }
    }

    static func managedINIValues(
        profile: ManagedINIProfile,
        settings: GameSettings
    ) -> [String: String] {
        var values: [String: String] = [:]
        for field in profile.fields {
            let value: String?
            switch field.source {
            case .width:
                value = (320...16_384).contains(settings.width) ? String(settings.width) : nil
            case .height:
                value = (240...16_384).contains(settings.height) ? String(settings.height) : nil
            case .fieldOfView:
                value = (50...140).contains(settings.fieldOfView) ? String(settings.fieldOfView) : nil
            case .verticalSync(let on, let off):
                value = settings.verticalSync ? on : off
            case .fullscreen(let on, let off):
                value = settings.displayMode == .exclusiveFullscreen ? on : off
            case .borderless(let on, let off):
                value = settings.displayMode == .borderlessFullscreen ? on : off
            }
            if let value { values[field.key] = value }
        }
        return values
    }

    /// Replace keys only inside an already-present section. No missing key or
    /// section is created, which keeps generated engine profiles authoritative.
    static func mergingExistingSectionValues(
        _ values: [String: String],
        into contents: String,
        section: String
    ) -> String {
        guard !values.isEmpty else { return contents }
        let newline = contents.contains("\r\n") ? "\r\n" : "\n"
        let hadTrailingNewline = contents.hasSuffix("\n")
        var lines = contents.components(separatedBy: newline)
        if hadTrailingNewline, lines.last == "" { lines.removeLast() }
        let heading = "[\(section)]"
        guard let sectionStart = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(heading) == .orderedSame
        }) else { return contents }
        let sectionEnd = lines[(sectionStart + 1)..<lines.endIndex].firstIndex(where: {
            let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.hasPrefix("[") && line.hasSuffix("]")
        }) ?? lines.endIndex

        for (key, value) in values {
            guard let index = lines[(sectionStart + 1)..<sectionEnd].firstIndex(where: { line in
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix(";"),
                      let separator = line.firstIndex(of: "=")
                else { return false }
                return line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(key) == .orderedSame
            }), let separator = lines[index].firstIndex(of: "=")
            else { continue }
            lines[index] = String(lines[index][...separator]) + value
        }
        let joined = lines.joined(separator: newline)
        return hadTrailingNewline ? joined + newline : joined
    }

    /// Replace existing quoted KeyValues entries such as
    /// `"setting.fullscreen" "0"`. The game owns the surrounding object and
    /// formatting; Secunda only changes the value for a key already present.
    static func mergingExistingQuotedKeyValues(
        _ values: [String: String],
        into contents: String
    ) -> String {
        guard !values.isEmpty, !contents.contains("\0") else { return contents }
        let newline = contents.contains("\r\n") ? "\r\n" : "\n"
        var lines = contents.components(separatedBy: newline)
        for lineIndex in lines.indices {
            var line = lines[lineIndex]
            for key in values.keys.sorted() {
                guard let value = values[key],
                      let valueRange = Self.quotedKeyValueValueRange(
                          for: key,
                          in: line
                      )
                else { continue }
                line.replaceSubrange(valueRange, with: value)
            }
            lines[lineIndex] = line
        }
        return lines.joined(separator: newline)
    }

    /// Returns the value span from an existing quoted KeyValues line. Keeping
    /// this parser line-local avoids regex escaping mistakes for dotted keys
    /// while preserving the file's original indentation and quote layout.
    private static func quotedKeyValueValueRange(
        for key: String,
        in line: String
    ) -> Range<String.Index>? {
        let keyToken = "\"\(key)\""
        guard let keyRange = line.range(of: keyToken),
              let openingQuote = line[keyRange.upperBound...].firstIndex(of: "\"")
        else { return nil }
        let valueStart = line.index(after: openingQuote)
        guard let valueEnd = line[valueStart...].firstIndex(of: "\"") else {
            return nil
        }
        return valueStart..<valueEnd
    }

    /// A managed profile is actionable only when every declared field already
    /// exists inside the exact generated section. This mirrors the writer's
    /// existing-key-only contract without changing the file.
    static func containsManagedFields(
        _ profile: ManagedINIProfile,
        in contents: String
    ) -> Bool {
        guard !profile.fields.isEmpty, !contents.contains("\0") else { return false }
        if profile.format == .quotedKeyValues {
            return profile.fields.allSatisfy { field in
                contents
                    .components(separatedBy: .newlines)
                    .contains { line in
                        Self.quotedKeyValueValueRange(for: field.key, in: line) != nil
                    }
            }
        }
        let lines = contents.components(separatedBy: .newlines)
        let heading = "[\(profile.section)]"
        guard let sectionStart = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(heading) == .orderedSame
        }) else { return false }
        let sectionEnd = lines[(sectionStart + 1)..<lines.endIndex].firstIndex(where: {
            let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.hasPrefix("[") && line.hasSuffix("]")
        }) ?? lines.endIndex
        let keys = Set(lines[(sectionStart + 1)..<sectionEnd].compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.hasPrefix(";"), let separator = line.firstIndex(of: "=") else {
                return nil
            }
            return line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        })
        return profile.fields.allSatisfy { keys.contains($0.key.lowercased()) }
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

    /// Replace existing numeric fields only inside a known nested Lua table.
    /// This keeps generic names such as x/y from touching unrelated gameplay
    /// data elsewhere in the generated preferences file.
    static func updatingLuaTableNumericValues(
        in contents: String,
        tablePath: [String],
        values: [String: String]
    ) -> String {
        guard !tablePath.isEmpty, !values.isEmpty else { return contents }
        var tableRange = contents.startIndex..<contents.endIndex
        for tableName in tablePath {
            guard let nested = luaTableBodyRange(
                named: tableName,
                in: contents,
                searchRange: tableRange
            ) else { return contents }
            tableRange = nested
        }

        var body = String(contents[tableRange])
        for key in values.keys.sorted() {
            guard let value = values[key] else { continue }
            body = updatingLuaNumericValue(
                in: body,
                keyCandidates: [key],
                value: value
            )
        }
        var updated = contents
        updated.replaceSubrange(tableRange, with: body)
        return updated
    }

    private static func luaTableBodyRange(
        named tableName: String,
        in contents: String,
        searchRange: Range<String.Index>
    ) -> Range<String.Index>? {
        let escaped = NSRegularExpression.escapedPattern(for: tableName)
        guard let regex = try? NSRegularExpression(
            pattern: "\\b\(escaped)\\b\\s*=\\s*\\{"
        ), let match = regex.firstMatch(
            in: contents,
            range: NSRange(searchRange, in: contents)
        ), let matchedRange = Range(match.range, in: contents),
           let openingBrace = contents[matchedRange].lastIndex(of: "{")
        else { return nil }

        var depth = 1
        var quote: Character?
        var isEscaped = false
        var index = contents.index(after: openingBrace)
        while index < searchRange.upperBound {
            let character = contents[index]
            if let activeQuote = quote {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return contents.index(after: openingBrace)..<index
                }
            }
            index = contents.index(after: index)
        }
        return nil
    }

    /// Device-resolution prefs entries hold 'W,H' or 'W,H,rate' as one
    /// quoted string. Rewrite width and height for keys the game has already
    /// written, preserving any trailing refresh rate; the table-valued
    /// options-definition form of the same key is left alone.
    static func updatingLuaAdapterValue(
        in contents: String,
        keyCandidates: [String],
        width: Int,
        height: Int
    ) -> String {
        for key in keyCandidates {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let pattern = "(\\b\(escaped)\\b\\s*=\\s*)(['\"])[0-9]+\\s*,\\s*[0-9]+([^'\"]*)(['\"])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(contents.startIndex..., in: contents)
            guard regex.firstMatch(in: contents, range: range) != nil else { continue }
            return regex.stringByReplacingMatches(
                in: contents,
                range: range,
                withTemplate: "$1$2\(width),\(height)$3$4"
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
        guard !values.isEmpty else { return contents }
        let heading = "[\(section)]"
        var document = INILineDocument(contents)

        guard let sectionStart = document.lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(heading) == .orderedSame
        }) else {
            if document.lines.last?.isEmpty == false { document.lines.append("") }
            document.lines.append(heading)
            document.lines.append(contentsOf: values.keys.sorted().map { "\($0)=\(values[$0]!)" })
            return document.serialized()
        }

        var sectionEnd = document.lines[(sectionStart + 1)..<document.lines.endIndex].firstIndex(where: {
            let line = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.hasPrefix("[") && line.hasSuffix("]")
        }) ?? document.lines.endIndex

        for key in values.keys.sorted() {
            let range = (sectionStart + 1)..<sectionEnd
            if let index = document.lines[range].firstIndex(where: {
                $0.split(separator: "=", maxSplits: 1).first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(key) == .orderedSame
            }) {
                document.lines[index] = "\(key)=\(values[key]!)"
            } else {
                document.lines.insert("\(key)=\(values[key]!)", at: sectionEnd)
                sectionEnd += 1
            }
        }

        return document.serialized()
    }

    /// Keeps profile rewrites byte-stable across Windows, Unix, and legacy
    /// line endings. Normalizing mixed separators once avoids treating the two
    /// bytes in a Windows separator as two independent blank lines.
    private struct INILineDocument {
        var lines: [String]
        let newline: String
        let hasTrailingNewline: Bool

        init(_ contents: String) {
            newline = Self.firstNewline(in: contents) ?? "\r\n"
            hasTrailingNewline = contents.isEmpty
                || contents.hasSuffix("\r\n")
                || contents.hasSuffix("\r")
                || contents.hasSuffix("\n")
            guard !contents.isEmpty else {
                lines = []
                return
            }
            let normalized = contents
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            lines = normalized.components(separatedBy: "\n")
            if lines.last == "" { lines.removeLast() }
        }

        func serialized() -> String {
            let contents = lines.joined(separator: newline)
            return hasTrailingNewline ? contents + newline : contents
        }

        private static func firstNewline(in contents: String) -> String? {
            var bytes = contents.utf8.makeIterator()
            while let byte = bytes.next() {
                if byte == 0x0D {
                    return bytes.next() == 0x0A ? "\r\n" : "\r"
                }
                if byte == 0x0A { return "\n" }
            }
            return nil
        }
    }

    private func preferencesDirectory(in bottleRoot: URL) -> URL {
        paths.activeWindowsUserDirectory(in: bottleRoot)
            .appendingPathComponent(
                "Documents/\(descriptor.documentsRelativePath)",
                isDirectory: true
            )
    }
}
