import Foundation

/// Filesystem acceptance for game-owned classic profiles. Every fixture lives
/// under a unique temporary root and is removed before the check ends.
enum ClassicProfileWriterSelfCheck {
    static func failures() -> [String] {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("secunda-classic-profile-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }

        let paths = SecundaPaths(
            applicationSupport: root.appendingPathComponent("support", isDirectory: true),
            repositoryRoot: nil,
            environment: [:]
        )
        let install = root.appendingPathComponent("game", isDirectory: true)
        let config = install.appendingPathComponent("AFFGame/Config", isDirectory: true)
        let systemURL = config.appendingPathComponent("AFFSystemSettings.ini")
        let gameURL = config.appendingPathComponent("AFFGame.ini")
        let defaultURL = config.appendingPathComponent("DefaultSystemSettings.ini")
        let insurgencyInstall = root.appendingPathComponent("insurgency-game", isDirectory: true)
        let insurgencyVideoURL = insurgencyInstall
            .appendingPathComponent("insurgency/cfg/video.txt")

        do {
            try manager.createDirectory(at: config, withIntermediateDirectories: true)
            var settings = LauncherSettings().game(.angelsFallFirst)
            settings.displayMode = .exclusiveFullscreen
            settings.width = 1600
            settings.height = 900
            settings.fieldOfView = 105
            settings.verticalSync = false
            settings.quality["unaccepted-option"] = "Ultra"

            let systemFixture = "[SystemSettings]\nResX=1280\nFullscreen=False\n"
            let gameFixture = "[AFFGame.AFFCamera]\nFOV=90\n"
            try systemFixture.write(to: systemURL, atomically: true, encoding: .utf8)
            try gameFixture.write(to: gameURL, atomically: true, encoding: .utf8)
            try "preserve-default".write(to: defaultURL, atomically: true, encoding: .utf8)

            let videoFixture = """
            "config"
            {
                "setting.fullscreen"    "1"
                "setting.nowindowborder"    "0"
                "setting.defaultres"    "1520"
                "setting.defaultresheight"    "984"
                "setting.mat_vsync"    "1"
                "preserve"    "yes"
            }
            """
            try manager.createDirectory(
                at: insurgencyVideoURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try videoFixture.write(to: insurgencyVideoURL, atomically: true, encoding: .utf8)

            var insurgencySettings = LauncherSettings().game(.insurgency)
            insurgencySettings.width = 1710
            insurgencySettings.height = 1107
            insurgencySettings.verticalSync = false
            try GameProfileWriter(paths: paths, descriptor: .insurgency).apply(
                insurgencySettings,
                bottleRoot: paths.bottleRoot,
                installRoot: insurgencyInstall
            )
            let updatedVideo = try String(contentsOf: insurgencyVideoURL, encoding: .utf8)
            guard updatedVideo.contains("\"setting.fullscreen\"    \"0\"")
                    && updatedVideo.contains("\"setting.nowindowborder\"    \"1\"")
                    && updatedVideo.contains("\"setting.defaultres\"    \"1710\"")
                    && updatedVideo.contains("\"setting.defaultresheight\"    \"1107\"")
                    && updatedVideo.contains("\"setting.mat_vsync\"    \"0\"")
                    && updatedVideo.contains("\"preserve\"    \"yes\"")
            else {
                return ["Insurgency video profile was not updated safely"]
            }

            let portalInstall = root.appendingPathComponent("portal-2-game", isDirectory: true)
            let portalVideoURL = portalInstall.appendingPathComponent("portal2/cfg/video.txt")
            try manager.createDirectory(
                at: portalVideoURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try videoFixture.write(to: portalVideoURL, atomically: true, encoding: .utf8)
            var portalSettings = LauncherSettings().game(.portal2)
            portalSettings.width = 1710
            portalSettings.height = 1107
            portalSettings.verticalSync = false
            try GameProfileWriter(paths: paths, descriptor: .portal2).apply(
                portalSettings,
                bottleRoot: paths.bottleRoot,
                installRoot: portalInstall
            )
            let updatedPortalVideo = try String(contentsOf: portalVideoURL, encoding: .utf8)
            guard updatedPortalVideo.contains("\"setting.defaultres\"    \"1710\"")
                    && updatedPortalVideo.contains("\"setting.mat_vsync\"    \"0\"")
                    && updatedPortalVideo.contains("\"preserve\"    \"yes\"")
            else {
                return ["Portal 2 video profile was not updated safely"]
            }

            try GameProfileWriter(paths: paths, descriptor: .angelsFallFirst).apply(
                settings,
                bottleRoot: paths.bottleRoot,
                installRoot: install
            )
            guard try String(contentsOf: systemURL, encoding: .utf8) == systemFixture,
                  try String(contentsOf: gameURL, encoding: .utf8) == gameFixture,
                  try String(contentsOf: defaultURL, encoding: .utf8) == "preserve-default"
            else {
                return ["game-owned profile was changed by unaccepted launcher settings"]
            }
            return []
        } catch {
            return ["game-owned profile filesystem check failed: \(error.localizedDescription)"]
        }
    }
}
