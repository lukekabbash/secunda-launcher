import Foundation

struct SecundaPaths: Sendable {
    let applicationSupport: URL
    let repositoryRoot: URL?

    init(
        applicationSupport: URL? = nil,
        repositoryRoot: URL? = SecundaPaths.discoverRepositoryRoot()
    ) {
        let supportRoot = applicationSupport ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        self.applicationSupport = supportRoot.appendingPathComponent(
            "Secunda Launcher",
            isDirectory: true
        )
        self.repositoryRoot = repositoryRoot
    }

    var bottleRoot: URL {
        bottlesDirectory
            .appendingPathComponent("SkyrimSE", isDirectory: true)
    }

    var bottlesDirectory: URL {
        applicationSupport.appendingPathComponent("Bottles", isDirectory: true)
    }

    var downloadsDirectory: URL {
        applicationSupport.appendingPathComponent("Downloads", isDirectory: true)
    }

    var steamInstaller: URL {
        downloadsDirectory.appendingPathComponent("SteamSetup.exe")
    }

    var logsDirectory: URL {
        applicationSupport.appendingPathComponent("Logs", isDirectory: true)
    }

    var cachesDirectory: URL {
        applicationSupport.appendingPathComponent("Caches", isDirectory: true)
    }

    var graphicsCacheDirectory: URL {
        cachesDirectory.appendingPathComponent("Graphics", isDirectory: true)
    }

    var backupsDirectory: URL {
        applicationSupport.appendingPathComponent("Backups", isDirectory: true)
    }

    var settingsFile: URL {
        applicationSupport.appendingPathComponent("settings.json")
    }

    var sourceRuntime: URL? {
        repositoryRoot?
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("wine", isDirectory: true)
    }

    func windowsUsersDirectory(in bottleRoot: URL) -> URL {
        bottleRoot.appendingPathComponent("drive_c/users", isDirectory: true)
    }

    func activeWindowsUserDirectory(in bottleRoot: URL) -> URL {
        let preferredNames = ["steamuser", NSUserName(), "secunda"]
        let manager = FileManager.default
        let windowsUsersDirectory = windowsUsersDirectory(in: bottleRoot)

        for name in preferredNames {
            let candidate = windowsUsersDirectory.appendingPathComponent(name, isDirectory: true)
            if manager.fileExists(atPath: candidate.path) { return candidate }
        }

        let excludedNames = Set(["all users", "default", "default user", "public"])
        let candidates = (try? manager.contentsOfDirectory(
            at: windowsUsersDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        if let discovered = candidates.first(where: { candidate in
            let isDirectory = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return isDirectory && !excludedNames.contains(candidate.lastPathComponent.lowercased())
        }) {
            return discovered
        }

        return windowsUsersDirectory.appendingPathComponent("secunda", isDirectory: true)
    }

    func activeWindowsUserDirectory() -> URL {
        activeWindowsUserDirectory(in: bottleRoot)
    }

    func prepareManagedDirectories() throws {
        let manager = FileManager.default
        for directory in [
            applicationSupport,
            bottlesDirectory,
            downloadsDirectory,
            logsDirectory,
            backupsDirectory,
            cachesDirectory,
            graphicsCacheDirectory
        ] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    static func discoverRepositoryRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL? {
        if let override = environment["SECUNDA_REPOSITORY_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        var candidate = currentDirectory.standardizedFileURL
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("Package.swift").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }
}
