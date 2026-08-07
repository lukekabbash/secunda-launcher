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
            "WINEESYNC": "1",
            "ROSETTA_ADVERTISE_AVX": "1",
            "SECUNDA_SOURCE_ONLY": "1",
            "DXMT_LOG_LEVEL": diagnostics ? "info" : "none",
            "DXMT_SHADER_CACHE_PATH": paths.graphicsCacheDirectory.path
        ]
        if diagnostics {
            environment["DXMT_LOG_PATH"] = paths.logsDirectory.path
        }
        let binPath = runtime.wineExecutable.deletingLastPathComponent().path
        let runtimeRoot = runtime.wineExecutable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let libraryPath = runtimeRoot.appendingPathComponent("lib").path
        environment["PATH"] = "\(binPath):/usr/bin:/bin:/usr/sbin:/sbin"
        environment["DYLD_LIBRARY_PATH"] = libraryPath
        return environment
    }

    private func candidates() -> [RuntimeCandidate] {
        var values: [RuntimeCandidate] = []

        if let override = ProcessInfo.processInfo.environment["SECUNDA_WINE_BIN"], !override.isEmpty {
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
            "lib/wine/x86_64-windows/xaudio2_7.dll",
            "lib/wine/x86_64-windows/xinput1_3.dll"
        ]
        return requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: runtimeRoot.appendingPathComponent($0).path)
        }
    }
}

private struct RuntimeCandidate {
    let url: URL
    let origin: RuntimeDescriptor.Origin
    let trustedRuntimeRoot: URL?
}
