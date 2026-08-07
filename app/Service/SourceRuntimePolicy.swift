import Foundation

enum SourceRuntimePolicy {
    static let provenanceRelativePath = "share/secunda/runtime-provenance.json"

    private static let forbiddenPathFragments = [
        "/crossover.app/",
        "/apple_gptk/",
        "/lib64/apple_gptk/",
        "libd3dshared.dylib"
    ]

    private static let removedEnvironmentKeys = [
        "CX_BOTTLE_PATH",
        "CX_ROOT",
        "DYLD_FALLBACK_LIBRARY_PATH",
        "DYLD_INSERT_LIBRARIES",
        "DYLD_LIBRARY_PATH",
        "PATH",
        "SECUNDA_CROSSOVER_APP",
        "WINEDLLPATH",
        "WINEDLLPATH64",
        "WINELOADER",
        "WINESERVER"
    ]

    private static let inheritedEnvironmentKeys = Set([
        "DISPLAY",
        "HOME",
        "LANG",
        "LC_ALL",
        "LC_CTYPE",
        "LOGNAME",
        "MallocNanoZone",
        "SECURITYSESSIONID",
        "TMPDIR",
        "USER",
        "XAUTHORITY",
        "__CF_USER_TEXT_ENCODING"
    ])

    static func allows(executable: URL, trustedRuntimeRoot: URL?) -> Bool {
        let resolvedExecutable = executable.resolvingSymlinksInPath().standardizedFileURL
        guard !containsForbiddenReference(resolvedExecutable.path) else { return false }

        let runtimeRoot = resolvedExecutable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if let trustedRuntimeRoot, !contains(resolvedExecutable, in: trustedRuntimeRoot) {
            return false
        }
        return hasProvenanceManifest(runtimeRoot: runtimeRoot)
    }

    static func containsForbiddenReference(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(of: "\\", with: "/").lowercased()
        return forbiddenPathFragments.contains { normalized.contains($0) }
    }

    static func sanitizedEnvironment(
        base: [String: String],
        overrides: [String: String]
    ) -> [String: String] {
        var environment = base.filter { key, _ in
            inheritedEnvironmentKeys.contains(key) || key.hasPrefix("LC_")
        }
        for key in removedEnvironmentKeys {
            environment.removeValue(forKey: key)
        }
        let permittedRemovedOverrides = Set(["DYLD_LIBRARY_PATH", "PATH"])
        for (key, value) in overrides
        where (!removedEnvironmentKeys.contains(key) || permittedRemovedOverrides.contains(key))
            && !containsForbiddenReference(value) {
            environment[key] = value
        }
        return environment
    }

    private static func hasProvenanceManifest(runtimeRoot: URL) -> Bool {
        let manifestURL = runtimeRoot.appendingPathComponent(provenanceRelativePath)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(RuntimeProvenance.self, from: data)
        else {
            return false
        }
        return manifest.formatVersion == 1
            && manifest.runtimeKind == "secunda-source-runtime"
            && manifest.architecture == "x86_64"
            && manifest.components.contains { $0.name == "Wine" && !$0.version.isEmpty }
            && manifest.components.contains { $0.name == "DXMT" && !$0.version.isEmpty }
    }

    private static func contains(_ file: URL, in root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let filePath = file.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }
}

private struct RuntimeProvenance: Decodable {
    let formatVersion: Int
    let runtimeKind: String
    let architecture: String
    let components: [RuntimeComponent]
}

private struct RuntimeComponent: Decodable {
    let name: String
    let version: String
}
