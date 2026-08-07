import Foundation

struct RuntimeDescriptor: Equatable, Sendable {
    let wineExecutable: URL
    let version: String
    let origin: Origin
    let bottleRoot: URL

    enum Origin: String, Sendable {
        case bundled = "Bundled runtime"
        case sourceBuild = "Source build"
        case environment = "Environment override"
    }

    func wineArguments(for command: [String]) -> [String] {
        command
    }
}

final class RuntimeManager {
    private let paths: SecundaPaths
    private let processRunner: ProcessRunner
    private let integrityLock = NSLock()
    private var verifiedIntegrityManifests: [String: Data] = [:]

    init(paths: SecundaPaths, processRunner: ProcessRunner) {
        self.paths = paths
        self.processRunner = processRunner
    }

    func locate() async -> RuntimeDescriptor? {
        for candidate in candidates() {
            guard FileManager.default.isExecutableFile(atPath: candidate.url.path) else { continue }
            guard SourceRuntimePolicy.allows(
                executable: candidate.url,
                trustedRuntimeRoot: candidate.trustedRuntimeRoot
            ) else { continue }
            guard hasMetalGraphicsBridge(beside: candidate.url) else { continue }
            guard await verifyRuntimeIntegrity(candidate) else { continue }
            let logURL = paths.logsDirectory.appendingPathComponent("runtime-probe.log")
            guard let result = try? await processRunner.run(
                executable: candidate.url,
                arguments: ["--version"],
                environment: [:],
                logURL: logURL
            ), result.terminationStatus == 0 else { continue }

            let version = (try? String(contentsOf: logURL, encoding: .utf8))?
                .split(whereSeparator: \.isNewline)
                .last
                .map(String.init)
            return RuntimeDescriptor(
                wineExecutable: candidate.url,
                version: version?.isEmpty == false ? version! : "Wine runtime",
                origin: candidate.origin,
                bottleRoot: paths.bottleRoot
            )
        }
        return nil
    }

    func environment(for runtime: RuntimeDescriptor, diagnostics: Bool) -> [String: String] {
        var environment: [String: String] = [
            "WINEPREFIX": runtime.bottleRoot.path,
            "WINEARCH": "win64",
            "WINEDLLOVERRIDES": "mscoree,mshtml=;winemenubuilder.exe=d;d3d10core,d3d11,dxgi=b",
            "WINEDEBUG": diagnostics ? "warn+all,err+all" : "-all",
            "WINEMSYNC": "1",
            "ROSETTA_ADVERTISE_AVX": "1",
            "SECUNDA_SOURCE_ONLY": "1",
            "SECUNDA_CEF_IN_PROCESS_GPU": "1",
            "DXMT_LOG_LEVEL": diagnostics ? "info" : "none",
            "DXMT_SHADER_CACHE_PATH": paths.graphicsCacheDirectory.path
        ]
        if diagnostics {
            environment["DXMT_LOG_PATH"] = paths.logsDirectory.path
        }
        environment.merge(
            Self.developmentPerformanceEnvironment(
                environment: ProcessInfo.processInfo.environment,
                repositoryRoot: paths.repositoryRoot
            ),
            uniquingKeysWith: { _, developmentValue in developmentValue }
        )
        let binPath = runtime.wineExecutable.deletingLastPathComponent().path
        environment["PATH"] = "\(binPath):/usr/bin:/bin:/usr/sbin:/sbin"
        let runtimeRoot = runtime.wineExecutable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // Every origin needs this, including the bundled runtime: winebus dlopens
        // libSDL2 by soname for controller support, and dlopen resolves a bare
        // soname through DYLD_LIBRARY_PATH rather than the loader's @rpath.
        environment["DYLD_LIBRARY_PATH"] = runtimeRoot.appendingPathComponent("lib").path

        // Vulkan over MoltenVK. The CrossOver-derived Wine loads Vulkan only
        // when both variables are present; games on the wined3d GL path are
        // unaffected because the per-launch d3d9 override still selects the
        // builtin there, and DXMT keeps owning d3d11.
        let moltenVK = runtimeRoot.appendingPathComponent("lib/libMoltenVK.dylib")
        if FileManager.default.fileExists(atPath: moltenVK.path) {
            environment["CX_LIBVULKAN"] = moltenVK.path
            environment["CX_ACTIVE_GRAPHICS_BACKEND"] = "wined3d"
        }
        return environment
    }

    private func candidates() -> [RuntimeCandidate] {
        var values: [RuntimeCandidate] = []

        if let override = Self.developmentRuntimeOverride(
            environment: ProcessInfo.processInfo.environment,
            repositoryRoot: paths.repositoryRoot
        ) {
            values.append(RuntimeCandidate(
                url: URL(fileURLWithPath: override),
                origin: .environment,
                trustedRuntimeRoot: nil
            ))
        }
        if let bundled = Bundle.main.resourceURL {
            let runtimeRoot = bundled.appendingPathComponent("runtime", isDirectory: true)
            values.append(RuntimeCandidate(
                url: runtimeRoot.appendingPathComponent("bin/wine64"),
                origin: .bundled,
                trustedRuntimeRoot: runtimeRoot
            ))
            values.append(RuntimeCandidate(
                url: runtimeRoot.appendingPathComponent("bin/wine"),
                origin: .bundled,
                trustedRuntimeRoot: runtimeRoot
            ))
        }
        if let sourceRuntime = paths.sourceRuntime {
            values.append(RuntimeCandidate(
                url: sourceRuntime.appendingPathComponent("bin/wine64"),
                origin: .sourceBuild,
                trustedRuntimeRoot: sourceRuntime
            ))
            values.append(RuntimeCandidate(
                url: sourceRuntime.appendingPathComponent("bin/wine"),
                origin: .sourceBuild,
                trustedRuntimeRoot: sourceRuntime
            ))
        }

        var seen = Set<String>()
        return values.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    static func developmentRuntimeOverride(
        environment: [String: String],
        repositoryRoot: URL?
    ) -> String? {
        guard environment["SECUNDA_DEVELOPER_MODE"] == "1",
              repositoryRoot != nil,
              let override = environment["SECUNDA_WINE_BIN"],
              !override.isEmpty
        else {
            return nil
        }
        return override
    }

    static func developmentPerformanceEnvironment(
        environment: [String: String],
        repositoryRoot: URL?
    ) -> [String: String] {
        guard environment["SECUNDA_DEVELOPER_MODE"] == "1",
              environment["SECUNDA_PERFORMANCE_CAPTURE"] == "1",
              repositoryRoot != nil
        else {
            return [:]
        }

        let requestedOpacity = environment["MTL_HUD_OPACITY"]
            .flatMap(Double.init)
            .flatMap { $0.isFinite ? $0 : nil }
        let opacity = requestedOpacity.map { min(max($0, 0), 1) } ?? 0
        var values = [
            "MTL_HUD_ENABLED": "1",
            "MTL_HUD_LOG_ENABLED": "1",
            "MTL_HUD_OPACITY": String(opacity)
        ]
        if environment["SECUNDA_SHADER_LOGGING"] == "1" {
            values["MTL_HUD_LOG_SHADER_ENABLED"] = "1"
        }
        return values
    }

    private func hasMetalGraphicsBridge(beside wineExecutable: URL) -> Bool {
        let runtimeRoot = wineExecutable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let requiredFiles = [
            "lib/libfreetype.6.dylib",
            "lib/libgnutls.30.dylib",
            "lib/wine/x86_64-unix/winemetal.so",
            "lib/wine/x86_64-unix/winecoreaudio.so",
            "lib/wine/x86_64-windows/d3d11.dll",
            "lib/wine/x86_64-windows/dxgi.dll",
            "lib/wine/x86_64-windows/x3daudio1_6.dll",
            "lib/wine/x86_64-windows/x3daudio1_7.dll",
            "lib/wine/x86_64-windows/xaudio2_6.dll",
            "lib/wine/x86_64-windows/xaudio2_7.dll",
            "lib/wine/x86_64-windows/xinput1_3.dll",
            "lib/wine/x86_64-windows/tasklist.exe"
        ]
        return requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: runtimeRoot.appendingPathComponent($0).path)
        }
    }

    private func verifyRuntimeIntegrity(_ candidate: RuntimeCandidate) async -> Bool {
        let runtimeRoot = candidate.url
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        switch RuntimeIntegrityPolicy.inspect(runtimeRoot: runtimeRoot) {
        case .absent:
            return candidate.origin != .bundled
        case .invalid:
            return false
        case .valid(let manifest, let data):
            let cacheKey = runtimeRoot.resolvingSymlinksInPath().standardizedFileURL.path
            if isRuntimeIntegrityCached(data, for: cacheKey) { return true }
            guard RuntimeIntegrityPolicy.validatesEntries(data, runtimeRoot: runtimeRoot) else {
                return false
            }

            guard let result = try? await processRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/shasum"),
                arguments: ["--status", "-a", "256", "-c", manifest.path],
                environment: ["PATH": "/usr/bin:/bin"],
                currentDirectory: runtimeRoot,
                logURL: paths.logsDirectory.appendingPathComponent("runtime-integrity.log")
            ), result.terminationStatus == 0 else {
                return false
            }
            cacheRuntimeIntegrity(data, for: cacheKey)
            return true
        }
    }

    private func isRuntimeIntegrityCached(_ data: Data, for key: String) -> Bool {
        integrityLock.lock()
        defer { integrityLock.unlock() }
        return verifiedIntegrityManifests[key] == data
    }

    private func cacheRuntimeIntegrity(_ data: Data, for key: String) {
        integrityLock.lock()
        defer { integrityLock.unlock() }
        verifiedIntegrityManifests[key] = data
    }
}

private struct RuntimeCandidate {
    let url: URL
    let origin: RuntimeDescriptor.Origin
    let trustedRuntimeRoot: URL?
}
