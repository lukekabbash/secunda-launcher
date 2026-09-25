import Foundation

/// Shipped INI templates for one Creation Engine title. Bethesda's launcher
/// copies these into `My Games` on its first run, but only when the files are
/// missing. Secunda writes display keys before that launcher ever runs, so
/// without seeding a fresh prefix gets a display-only stub `*Prefs.ini` and
/// the engine starts with almost no renderer configuration.
struct CreationEngineINISeed: Equatable, Sendable {
    /// Main engine INI (`Skyrim.ini`) and the shipped defaults it is copied from.
    let mainFileName: String
    let mainTemplates: [String]
    /// Complete shipped prefs file the launcher uses as its baseline.
    let prefsBaselines: [String]
    /// Quality presets layered over the baseline, most preferred first.
    /// All paths are relative to the install root; the first file found wins.
    let prefsPresets: [String]
}

extension GameDescriptor {
    /// Medium is the first choice: it is the launcher's own preset for
    /// mid-range GPUs and leaves headroom on base Apple-silicon Macs.
    var creationEngineINISeed: CreationEngineINISeed? {
        switch id {
        case "skyrim-se":
            return Self.creationEngineSeed(
                mainFileName: "Skyrim.ini",
                folder: "Skyrim",
                prefsFileName: "SkyrimPrefs.ini"
            )
        case "fallout-4":
            return Self.creationEngineSeed(
                mainFileName: "Fallout4.ini",
                folder: "Fallout4",
                prefsFileName: "Fallout4Prefs.ini"
            )
        default:
            return nil
        }
    }

    private static func creationEngineSeed(
        mainFileName: String,
        folder: String,
        prefsFileName: String
    ) -> CreationEngineINISeed {
        func candidates(_ names: [String]) -> [String] {
            names.flatMap { ["\(folder)/\($0)", $0] }
        }
        let stem = (mainFileName as NSString).deletingPathExtension
        return CreationEngineINISeed(
            mainFileName: mainFileName,
            mainTemplates: ["\(stem)_Default.ini"],
            prefsBaselines: candidates([prefsFileName]),
            prefsPresets: candidates(["Medium.ini", "High.ini", "Low.ini"])
        )
    }
}

enum CreationEngineINISeeder {
    /// Shipped INIs are a few tens of kilobytes; anything larger is not one.
    static let maximumTemplateBytes = 1_048_576

    /// Seed missing or stub INIs in `preferencesDirectory` from the install's
    /// shipped templates. Complete player-owned files are never touched.
    /// Returns the file names that were written.
    @discardableResult
    static func seed(
        _ seed: CreationEngineINISeed,
        prefsFileName: String,
        preferencesDirectory: URL,
        installRoot: URL
    ) throws -> [String] {
        var written: [String] = []

        let mainURL = preferencesDirectory.appendingPathComponent(seed.mainFileName)
        if !FileManager.default.fileExists(atPath: mainURL.path),
           let template = firstTemplate(seed.mainTemplates, in: installRoot) {
            try template.write(to: mainURL, options: .atomic)
            written.append(seed.mainFileName)
        }

        let prefsURL = preferencesDirectory.appendingPathComponent(prefsFileName)
        let existing: INIText?
        if FileManager.default.fileExists(atPath: prefsURL.path) {
            // An unreadable player file is left alone rather than replaced.
            guard let readable = INIText(contentsOf: prefsURL) else { return written }
            guard isDisplayOnlyStub(readable.text) else { return written }
            existing = readable
        } else {
            existing = nil
        }
        guard let seeded = seededPrefs(seed, installRoot: installRoot) else { return written }
        // Carry forward anything an earlier Secunda launch wrote so the
        // player's display and quality choices survive the repair.
        let carried = existing.map { displayValues(in: $0.text) } ?? [:]
        let merged = GameProfileWriter.mergingDisplayValues(carried, into: seeded.text)
        try INIText(text: merged, encoding: seeded.encoding).write(to: prefsURL)
        written.append(prefsFileName)
        return written
    }

    /// The launcher's own recipe: the shipped baseline with a quality preset
    /// merged over it. Either half alone is used when the other is missing.
    static func seededPrefs(_ seed: CreationEngineINISeed, installRoot: URL) -> INIText? {
        let baseline = firstTemplate(seed.prefsBaselines, in: installRoot).flatMap(INIText.init(data:))
        let preset = firstTemplate(seed.prefsPresets, in: installRoot).flatMap(INIText.init(data:))
        guard var result = baseline ?? preset else { return nil }
        if baseline != nil, let preset {
            for (section, values) in sectionValues(in: preset.text) {
                result.text = GameProfileWriter.mergingSectionValues(
                    values,
                    into: result.text,
                    section: section
                )
            }
        }
        return result
    }

    /// True for an empty file or one whose only section is `[Display]`: the
    /// shape Secunda's writer produced before seeding existed. A launcher- or
    /// game-generated prefs file always carries many sections.
    static func isDisplayOnlyStub(_ contents: String) -> Bool {
        sectionNames(in: contents).allSatisfy { $0.caseInsensitiveCompare("Display") == .orderedSame }
    }

    static func sectionNames(in contents: String) -> [String] {
        contents.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 else {
                return nil
            }
            return String(trimmed.dropFirst().dropLast())
        }
    }

    static func displayValues(in contents: String) -> [String: String] {
        sectionValues(in: contents)
            .first { $0.section.caseInsensitiveCompare("Display") == .orderedSame }?
            .values ?? [:]
    }

    /// Key/value pairs per section, in file order. Comments are skipped.
    static func sectionValues(in contents: String) -> [(section: String, values: [String: String])] {
        var result: [(section: String, values: [String: String])] = []
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 {
                result.append((String(trimmed.dropFirst().dropLast()), [:]))
                continue
            }
            guard !result.isEmpty, !trimmed.hasPrefix(";"), !trimmed.hasPrefix("#"),
                  let separator = trimmed.firstIndex(of: "=")
            else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[result.count - 1].values[key] = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// First candidate that resolves, case-insensitively, to a bounded regular
    /// file inside `installRoot`. Symlinks and escapes are rejected.
    static func firstTemplate(_ candidates: [String], in installRoot: URL) -> Data? {
        let root = installRoot.standardizedFileURL
        for candidate in candidates {
            guard let url = resolve(candidate, in: root),
                  let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
                  ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  size > 0, size <= maximumTemplateBytes,
                  let data = try? Data(contentsOf: url),
                  !data.contains(0),
                  let text = INIText(data: data),
                  !sectionNames(in: text.text).isEmpty
            else { continue }
            return data
        }
        return nil
    }

    private static func resolve(_ relativePath: String, in root: URL) -> URL? {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return nil }
        var current = root
        for component in components {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: current.path),
                  let match = entries.first(where: {
                      $0.caseInsensitiveCompare(component) == .orderedSame
                  })
            else { return nil }
            current = current.appendingPathComponent(match)
        }
        let resolved = current.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        return resolved.hasPrefix(resolvedRoot + "/") ? current : nil
    }
}

/// INI text with the encoding it was read in. Bethesda INIs are usually
/// ASCII, but localized installs can carry Windows-1252 bytes; reading those
/// as UTF-8 fails, and a failed read must never be mistaken for an empty file.
struct INIText {
    var text: String
    var encoding: String.Encoding

    init(text: String, encoding: String.Encoding) {
        self.text = text
        self.encoding = encoding
    }

    init?(data: Data) {
        if let text = String(data: data, encoding: .utf8) {
            self.init(text: text, encoding: .utf8)
        } else if let text = String(data: data, encoding: .windowsCP1252) {
            self.init(text: text, encoding: .windowsCP1252)
        } else if let text = String(data: data, encoding: .isoLatin1) {
            self.init(text: text, encoding: .isoLatin1)
        } else {
            return nil
        }
    }

    init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    func write(to url: URL) throws {
        guard let data = text.data(using: encoding) ?? text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: .atomic)
    }
}
