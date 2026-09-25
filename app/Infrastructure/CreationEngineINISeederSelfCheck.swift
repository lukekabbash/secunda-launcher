import Foundation

/// Filesystem acceptance for first-run Creation Engine INI seeding. Every
/// fixture lives under a unique temporary root and is removed afterwards.
enum CreationEngineINISeederSelfCheck {
    static func failures() -> [String] {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("secunda-ini-seed-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }

        let paths = SecundaPaths(
            applicationSupport: root.appendingPathComponent("support", isDirectory: true),
            repositoryRoot: nil,
            environment: [:]
        )
        let descriptor = GameDescriptor.skyrimSE
        guard let seed = descriptor.creationEngineINISeed,
              let prefsFileName = descriptor.prefsFileName
        else { return ["Skyrim has no INI seed plan"] }

        let install = root.appendingPathComponent("Skyrim Special Edition", isDirectory: true)
        let presets = install.appendingPathComponent("Skyrim", isDirectory: true)
        let defaultMain = "[General]\r\nsLanguage=ENGLISH\r\n"
        let baseline = "[Display]\r\niShadowMapResolution=4096\r\nbSAOEnable=1\r\n"
            + "[Launcher]\r\nbEnableFileSelection=1\r\n[General]\r\nfBrightLightColorB=1.0000\r\n"
        let medium = "[Display]\r\niShadowMapResolution=2048\r\n[Grass]\r\nfGrassStartFadeDistance=3500.0000\r\n"

        do {
            try manager.createDirectory(at: presets, withIntermediateDirectories: true)
            try defaultMain.write(
                to: install.appendingPathComponent("Skyrim_Default.ini"),
                atomically: true,
                encoding: .utf8
            )
            try baseline.write(to: presets.appendingPathComponent("SkyrimPrefs.ini"), atomically: true, encoding: .utf8)
            // Lower-case on disk: lookup must not depend on the volume's case rules.
            try medium.write(to: presets.appendingPathComponent("medium.ini"), atomically: true, encoding: .utf8)

            try paths.prepareManagedDirectories()
            try BottleManager.preparePrivateDocuments(paths: paths, bottleRoot: paths.bottleRoot)
            let preferences = paths.activeWindowsUserDirectory(in: paths.bottleRoot)
                .appendingPathComponent("Documents/\(descriptor.documentsRelativePath)", isDirectory: true)
            let prefsURL = preferences.appendingPathComponent(prefsFileName)
            let mainURL = preferences.appendingPathComponent(seed.mainFileName)

            // 1. Fresh prefix: the writer seeds before applying display keys.
            var settings = LauncherSettings().game(descriptor)
            settings.displayMode = .borderlessFullscreen
            settings.width = 1470
            settings.height = 956
            let writer = GameProfileWriter(paths: paths, descriptor: descriptor)
            try writer.apply(settings, bottleRoot: paths.bottleRoot, installRoot: install)

            guard try String(contentsOf: mainURL, encoding: .utf8) == defaultMain else {
                return ["fresh prefix did not copy Skyrim_Default.ini to Skyrim.ini"]
            }
            let fresh = try String(contentsOf: prefsURL, encoding: .utf8)
            let freshSections = Set(CreationEngineINISeeder.sectionNames(in: fresh))
            let freshDisplay = CreationEngineINISeeder.displayValues(in: fresh)
            guard freshSections.isSuperset(of: ["Display", "Launcher", "General", "Grass"]),
                  freshDisplay["iShadowMapResolution"] == "2048",
                  freshDisplay["bSAOEnable"] == "1",
                  freshDisplay["iSize W"] == "1470",
                  freshDisplay["iSize H"] == "956",
                  freshDisplay["bBorderless"] == "1"
            else {
                return ["fresh prefix prefs were not baseline + Medium + display keys"]
            }

            // 2. A later launch never re-seeds a complete file.
            let tuned = fresh.replacingOccurrences(
                of: "fBrightLightColorB=1.0000",
                with: "fBrightLightColorB=0.5000"
            )
            try tuned.write(to: prefsURL, atomically: true, encoding: .utf8)
            try "[General]\r\nsLanguage=FRENCH\r\n".write(to: mainURL, atomically: true, encoding: .utf8)
            let rewritten = try CreationEngineINISeeder.seed(
                seed,
                prefsFileName: prefsFileName,
                preferencesDirectory: preferences,
                installRoot: install
            )
            guard rewritten.isEmpty,
                  try String(contentsOf: prefsURL, encoding: .utf8) == tuned,
                  try String(contentsOf: mainURL, encoding: .utf8).contains("FRENCH")
            else {
                return ["seeding replaced a complete player-owned INI"]
            }

            // 3. The display-only stub older builds wrote is repaired and keeps its values.
            try "[Display]\r\nbBorderless=0\r\niSize W=1234\r\nfShadowDistance=0.0000\r\n"
                .write(to: prefsURL, atomically: true, encoding: .utf8)
            let repaired = try CreationEngineINISeeder.seed(
                seed,
                prefsFileName: prefsFileName,
                preferencesDirectory: preferences,
                installRoot: install
            )
            let repairedText = try String(contentsOf: prefsURL, encoding: .utf8)
            let repairedDisplay = CreationEngineINISeeder.displayValues(in: repairedText)
            guard repaired == [prefsFileName],
                  CreationEngineINISeeder.sectionNames(in: repairedText).contains("Launcher"),
                  repairedDisplay["iSize W"] == "1234",
                  repairedDisplay["fShadowDistance"] == "0.0000",
                  repairedDisplay["iShadowMapResolution"] == "2048"
            else {
                return ["display-only stub was not repaired with its values preserved"]
            }

            // 4. Windows-1252 bytes survive a display rewrite instead of being
            // read as empty and replaced by a stub.
            var legacy = Data("[General]\r\n; caf".utf8)
            legacy.append(0xE9)
            legacy.append(contentsOf: Data("\r\n[Launcher]\r\nbEnableFileSelection=1\r\n[Display]\r\niSize W=800\r\n".utf8))
            try legacy.write(to: prefsURL)
            try writer.apply(settings, bottleRoot: paths.bottleRoot, installRoot: install)
            let legacyAfter = try Data(contentsOf: prefsURL)
            guard legacyAfter.contains(0xE9),
                  let legacyText = String(data: legacyAfter, encoding: .windowsCP1252),
                  CreationEngineINISeeder.displayValues(in: legacyText)["iSize W"] == "1470",
                  CreationEngineINISeeder.sectionNames(in: legacyText).contains("Launcher")
            else {
                return ["non-UTF-8 prefs file was not preserved through a display rewrite"]
            }

            // 5. Templates reached through a symlink or missing entirely seed nothing.
            let outside = root.appendingPathComponent("outside.ini")
            try baseline.write(to: outside, atomically: true, encoding: .utf8)
            let linkedInstall = root.appendingPathComponent("linked-install", isDirectory: true)
            try manager.createDirectory(
                at: linkedInstall.appendingPathComponent("Skyrim", isDirectory: true),
                withIntermediateDirectories: true
            )
            try manager.createSymbolicLink(
                at: linkedInstall.appendingPathComponent("Skyrim/SkyrimPrefs.ini"),
                withDestinationURL: outside
            )
            guard CreationEngineINISeeder.seededPrefs(seed, installRoot: linkedInstall) == nil,
                  CreationEngineINISeeder.seededPrefs(
                      seed,
                      installRoot: root.appendingPathComponent("empty-install", isDirectory: true)
                  ) == nil
            else {
                return ["INI seeding followed a symlink or invented a template"]
            }

            guard GameDescriptor.fallout4.creationEngineINISeed?.mainTemplates == ["Fallout4_Default.ini"],
                  GameDescriptor.enderalSE.creationEngineINISeed == nil,
                  GameDescriptor.insurgency.creationEngineINISeed == nil
            else {
                return ["INI seed plans are not title scoped"]
            }
            return []
        } catch {
            return ["INI seeding filesystem check failed: \(error.localizedDescription)"]
        }
    }
}
