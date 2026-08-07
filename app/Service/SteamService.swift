import Foundation

final class SteamService {
    static let officialInstallerURL = URL(
        string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
    )!
    static let compatibilityArguments = [
        "-system-composer",
        "-no-cef-sandbox",
        "-cef-allow-browser-underlays"
    ]
    static let interactiveOutput: ProcessOutput = .discard
    private let paths: SecundaPaths
    private let processRunner: ProcessRunner
    private let runtimeManager: RuntimeManager

    init(paths: SecundaPaths, processRunner: ProcessRunner, runtimeManager: RuntimeManager) {
        self.paths = paths
        self.processRunner = processRunner
        self.runtimeManager = runtimeManager
    }

    func executable(in runtime: RuntimeDescriptor?) -> URL? {
        let bottleRoot = runtime?.bottleRoot ?? paths.bottleRoot
        let candidates = [
            bottleRoot.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe"),
            bottleRoot.appendingPathComponent("drive_c/Program Files/Steam/steam.exe")
        ]
        return candidates.first { isSafeRegularFile($0, in: bottleRoot) }
    }

    func downloadInstaller() async throws -> URL {
        try paths.prepareManagedDirectories()
        let (temporaryURL, response) = try await URLSession.shared.download(from: Self.officialInstallerURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if FileManager.default.fileExists(atPath: paths.steamInstaller.path) {
            try FileManager.default.removeItem(at: paths.steamInstaller)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: paths.steamInstaller)
        return paths.steamInstaller
    }

    func install(runtime: RuntimeDescriptor, diagnostics: Bool) async throws {
        let installer = FileManager.default.fileExists(atPath: paths.steamInstaller.path)
            ? paths.steamInstaller
            : try await downloadInstaller()

        let result = try await processRunner.run(
            executable: runtime.wineExecutable,
            arguments: runtime.wineArguments(for: [installer.path, "/S"]),
            environment: runtimeManager.environment(for: runtime, diagnostics: diagnostics),
            currentDirectory: paths.downloadsDirectory,
            logURL: paths.logsDirectory.appendingPathComponent("steam-install.log")
        )
        guard result.terminationStatus == 0 else {
            throw ProcessRunnerError.nonZeroExit(result.terminationStatus, result.logURL)
        }
    }

    @discardableResult
    func launch(
        runtime: RuntimeDescriptor,
        arguments: [String] = [],
        diagnostics: Bool
    ) throws -> Int32 {
        guard let executable = executable(in: runtime) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try processRunner.launch(
            executable: runtime.wineExecutable,
            arguments: runtime.wineArguments(for: [
                executable.path
            ] + Self.compatibilityArguments + arguments),
            environment: runtimeManager.environment(for: runtime, diagnostics: diagnostics),
            currentDirectory: executable.deletingLastPathComponent(),
            output: Self.interactiveOutput
        )
    }

    private func isSafeRegularFile(_ candidate: URL, in bottleRoot: URL) -> Bool {
        guard paths.contains(candidate, inBottleRoot: bottleRoot),
              let values = try? candidate.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey
              ])
        else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

}
