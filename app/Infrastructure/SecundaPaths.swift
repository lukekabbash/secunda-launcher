import Foundation

struct SecundaPaths: Sendable {
    static let defaultBottleName = "SkyrimSE"

    let applicationSupport: URL
    let repositoryRoot: URL?
    let bottleName: String
    let bottleOverrideError: String?

    init(
        applicationSupport: URL? = nil,
        repositoryRoot: URL? = SecundaPaths.discoverRepositoryRoot(),
        environment: [String: String] = ProcessInfo.processInfo.environment
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
        if let requestedName = environment["SECUNDA_BOTTLE_NAME"] {
            if environment["SECUNDA_DEVELOPER_MODE"] != "1" || repositoryRoot == nil {
                self.bottleName = Self.defaultBottleName
                self.bottleOverrideError = "SECUNDA_BOTTLE_NAME is available only in explicit source-development mode."
            } else if let validatedName = Self.validatedBottleName(requestedName) {
                self.bottleName = validatedName
                self.bottleOverrideError = nil
            } else {
                self.bottleName = Self.defaultBottleName
                self.bottleOverrideError = "SECUNDA_BOTTLE_NAME must be one safe folder name inside Secunda’s managed Bottles directory."
            }
        } else {
            self.bottleName = Self.defaultBottleName
            self.bottleOverrideError = nil
        }
    }

    var bottleRoot: URL {
        bottlesDirectory
            .appendingPathComponent(bottleName, isDirectory: true)
    }

    var usesBottleOverride: Bool {
        bottleName != Self.defaultBottleName
    }

    func isManagedBottleRoot(_ candidate: URL) -> Bool {
        guard bottleOverrideError == nil else { return false }
        let managedSupport = applicationSupport.resolvingSymlinksInPath().standardizedFileURL.path
        let managedBottles = bottlesDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let lexicalCandidate = candidate.standardizedFileURL
        let resolvedName = URL(fileURLWithPath: resolvedCandidate).lastPathComponent

        return managedBottles.hasPrefix(managedSupport + "/")
            && lexicalCandidate.deletingLastPathComponent() == bottlesDirectory.standardizedFileURL
            && resolvedCandidate.hasPrefix(managedBottles + "/")
            && Self.validatedBottleName(resolvedName) != nil
    }

    func contains(_ candidate: URL, inBottleRoot bottleRoot: URL) -> Bool {
        guard isManagedBottleRoot(bottleRoot) else { return false }
        let resolvedBottle = bottleRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedCandidate.hasPrefix(resolvedBottle + "/")
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

    /// Player-supplied cover art, named after a game's identifier. Used in
    /// preference to Steam's CDN so anyone can restyle their library.
    var artworkDirectory: URL {
        applicationSupport.appendingPathComponent("Artwork", isDirectory: true)
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
            artworkDirectory,
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

    static func validatedBottleName(_ candidate: String?) -> String? {
        guard let candidate,
              !candidate.isEmpty,
              candidate.utf8.count <= 64,
              candidate.first != ".",
              !candidate.contains("..")
        else {
            return nil
        }

        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
        )
        guard candidate.unicodeScalars.allSatisfy(allowed.contains) else { return nil }

        let normalized = candidate.lowercased()
        let forbiddenFragments = ["crossover", "cross-over", "cross_over", "codeweavers", "cxbottle"]
        guard !forbiddenFragments.contains(where: normalized.contains) else { return nil }
        return candidate
    }
}
