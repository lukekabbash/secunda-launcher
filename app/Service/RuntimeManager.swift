import Foundation

struct RuntimeDescriptor: Equatable, Sendable {
    let wineExecutable: URL
    let version: String
    let origin: Origin
    let engine: Engine
    let bottleRoot: URL
    let bottleContainer: URL
    let bottleName: String?
    let bottleExecutable: URL?

    enum Engine: String, Equatable, Sendable {
        case bundledWine = "Bundled Wine"
        case crossOver = "CrossOver"
    }

    enum Origin: String, Sendable {
        case bundled = "Bundled runtime"
        case sourceBuild = "Source build"
        case configured = "Selected runtime"
        case environment = "Environment override"
        case crossOver = "CrossOver runtime"
        case crossOverDevelopment = "CrossOver local runtime"
    }

    var isCrossOver: Bool {
        engine == .crossOver
    }

    func wineArguments(for command: [String]) -> [String] {
        guard let bottleName else { return command }
        return ["--bottle", bottleName] + command
    }
}

final class RuntimeManager {
    private let paths: SecundaPaths
    private let processRunner: ProcessRunner

    init(paths: SecundaPaths, processRunner: ProcessRunner) {
        self.paths = paths
        self.processRunner = processRunner
    }

    func locate(settings: LauncherSettings) async -> RuntimeDescriptor? {
        if let crossOver = CrossOverRuntimeLocator(paths: paths).locate() {
            return RuntimeDescriptor(
                wineExecutable: crossOver.wineExecutable,
                version: crossOver.version,
                origin: crossOver.origin,
                engine: .crossOver,
                bottleRoot: paths.crossOverBottleRoot,
                bottleContainer: paths.bottlesDirectory,
                bottleName: paths.crossOverBottleName,
                bottleExecutable: crossOver.bottleExecutable
            )
        }

        for candidate in candidates(settings: settings) {
            guard FileManager.default.isExecutableFile(atPath: candidate.url.path) else { continue }
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
                engine: .bundledWine,
                bottleRoot: paths.bottleRoot,
                bottleContainer: paths.bottlesDirectory,
                bottleName: nil,
                bottleExecutable: nil
            )
        }
        return nil
    }

    func environment(for runtime: RuntimeDescriptor, diagnostics: Bool) -> [String: String] {
        if runtime.isCrossOver {
            var environment: [String: String] = [
                "CX_BOTTLE_PATH": runtime.bottleContainer.path,
                "ROSETTA_ADVERTISE_AVX": "1",
                "WINEDEBUG": diagnostics ? "warn+all,err+all" : "-all"
            ]
            if diagnostics {
                environment["DXMT_LOG_LEVEL"] = "info"
            }
            return environment
        }

        var environment: [String: String] = [
            "WINEPREFIX": runtime.bottleRoot.path,
            "WINEARCH": "win64",
            "WINEDLLOVERRIDES": "mscoree,mshtml=;winemenubuilder.exe=d;d3d10core,d3d11,dxgi=b",
            "WINEDEBUG": diagnostics ? "warn+all,err+all" : "-all",
            "WINEESYNC": "1",
            "ROSETTA_ADVERTISE_AVX": "1",
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
        environment["PATH"] = "\(binPath):\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")"
        environment["DYLD_LIBRARY_PATH"] = [
            libraryPath,
            ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"]
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ":")
        return environment
    }

    private func candidates(settings: LauncherSettings) -> [(url: URL, origin: RuntimeDescriptor.Origin)] {
        var values: [(URL, RuntimeDescriptor.Origin)] = []

        if let override = ProcessInfo.processInfo.environment["SECUNDA_WINE_BIN"], !override.isEmpty {
            values.append((URL(fileURLWithPath: override), .environment))
        }
        if let bundled = Bundle.main.resourceURL {
            values.append((bundled.appendingPathComponent("runtime/bin/wine64"), .bundled))
            values.append((bundled.appendingPathComponent("runtime/bin/wine"), .bundled))
        }
        if let sourceRuntime = paths.sourceRuntime {
            values.append((sourceRuntime.appendingPathComponent("bin/wine64"), .sourceBuild))
            values.append((sourceRuntime.appendingPathComponent("bin/wine"), .sourceBuild))
        }
        if let configured = settings.runtimeExecutablePath, !configured.isEmpty {
            values.append((URL(fileURLWithPath: configured), .configured))
        }

        var seen = Set<String>()
        return values.filter { seen.insert($0.0.standardizedFileURL.path).inserted }
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
