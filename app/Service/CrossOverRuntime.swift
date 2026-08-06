import Foundation

struct CrossOverInstallation: Equatable, Sendable {
    let applicationURL: URL
    let supportURL: URL
    let wineExecutable: URL
    let bottleExecutable: URL
    let version: String
    let origin: RuntimeDescriptor.Origin
}

struct CrossOverRuntimeLocator {
    private let paths: SecundaPaths
    private let fileManager: FileManager
    private let environment: [String: String]

    init(
        paths: SecundaPaths,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.environment = environment
    }

    func locate() -> CrossOverInstallation? {
        candidates().lazy.compactMap(installation(at:)).first
    }

    private func candidates() -> [(URL, RuntimeDescriptor.Origin)] {
        var candidates: [(URL, RuntimeDescriptor.Origin)] = []

        if let override = environment["SECUNDA_CROSSOVER_APP"], !override.isEmpty {
            candidates.append((URL(fileURLWithPath: override, isDirectory: true), .environment))
        }

        candidates.append((URL(fileURLWithPath: "/Applications/CrossOver.app", isDirectory: true), .crossOver))
        candidates.append((
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/CrossOver.app", isDirectory: true),
            .crossOver
        ))

        for developmentRoot in developmentRoots() {
            candidates.append((
                developmentRoot.appendingPathComponent("build/vendor/CrossOver.app", isDirectory: true),
                .crossOverDevelopment
            ))
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.0.standardizedFileURL.path).inserted }
    }

    private func installation(at candidate: (URL, RuntimeDescriptor.Origin)) -> CrossOverInstallation? {
        let applicationURL = normalizedApplicationURL(candidate.0)
        let supportURL = applicationURL
            .appendingPathComponent("Contents/SharedSupport/CrossOver", isDirectory: true)
        let wineExecutable = supportURL.appendingPathComponent("bin/wine")
        let bottleExecutable = supportURL.appendingPathComponent("bin/cxbottle")
        let requiredPaths = [
            wineExecutable,
            bottleExecutable,
            supportURL.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll"),
            supportURL.appendingPathComponent("lib64/apple_gptk/wine/x86_64-windows/d3d11.dll"),
            supportURL.appendingPathComponent("lib64/apple_gptk/external/libd3dshared.dylib")
        ]
        guard requiredPaths.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            return nil
        }
        guard fileManager.isExecutableFile(atPath: wineExecutable.path),
              fileManager.isExecutableFile(atPath: bottleExecutable.path)
        else {
            return nil
        }

        return CrossOverInstallation(
            applicationURL: applicationURL,
            supportURL: supportURL,
            wineExecutable: wineExecutable,
            bottleExecutable: bottleExecutable,
            version: applicationVersion(at: applicationURL),
            origin: candidate.1
        )
    }

    private func normalizedApplicationURL(_ candidate: URL) -> URL {
        if candidate.lastPathComponent == "CrossOver" {
            return candidate
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        return candidate
    }

    private func developmentRoots() -> [URL] {
        var roots: [URL] = []
        if let repositoryRoot = paths.repositoryRoot {
            roots.append(repositoryRoot)
        }

        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent()
        if bundleParent.lastPathComponent == "dist" {
            roots.append(bundleParent.deletingLastPathComponent())
        }

        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func applicationVersion(at applicationURL: URL) -> String {
        let infoURL = applicationURL.appendingPathComponent("Contents/Info.plist")
        let values = NSDictionary(contentsOf: infoURL) as? [String: Any]
        return values?["CFBundleShortVersionString"] as? String ?? "CrossOver runtime"
    }
}
