import Foundation

final class BottleManager {
    private let paths: SecundaPaths
    private let processRunner: ProcessRunner
    private let runtimeManager: RuntimeManager

    init(paths: SecundaPaths, processRunner: ProcessRunner, runtimeManager: RuntimeManager) {
        self.paths = paths
        self.processRunner = processRunner
        self.runtimeManager = runtimeManager
    }

    func isInitialized(runtime: RuntimeDescriptor?) -> Bool {
        let bottleRoot = runtime?.bottleRoot ?? paths.bottleRoot
        return FileManager.default.fileExists(atPath: bottleRoot.appendingPathComponent("system.reg").path)
            && FileManager.default.fileExists(atPath: bottleRoot.appendingPathComponent("drive_c").path)
    }

    func initialize(runtime: RuntimeDescriptor, diagnostics: Bool) async throws {
        try paths.prepareManagedDirectories()

        if isInitialized(runtime: runtime) {
            try await configureMacDisplay(runtime: runtime, diagnostics: diagnostics)
            return
        }

        try await createWineBottle(runtime: runtime, diagnostics: diagnostics)

        try await configureMacDisplay(runtime: runtime, diagnostics: diagnostics)
    }

    func applyGameCompatibility(runtime: RuntimeDescriptor, diagnostics: Bool) async throws {
        let values = ["x3daudio1_6", "x3daudio1_7", "xaudio2_6", "xaudio2_7"]
        let environment = runtimeManager.environment(for: runtime, diagnostics: diagnostics)
        let logURL = paths.logsDirectory.appendingPathComponent("game-compatibility.log")

        for name in values {
            let result = try await processRunner.run(
                executable: runtime.wineExecutable,
                arguments: runtime.wineArguments(for: [
                    "reg", "add", "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides",
                    "/v", name, "/t", "REG_SZ", "/d", "builtin", "/f"
                ]),
                environment: environment,
                currentDirectory: runtime.bottleRoot,
                logURL: logURL
            )
            guard result.terminationStatus == 0 else {
                throw ProcessRunnerError.nonZeroExit(result.terminationStatus, result.logURL)
            }
        }
    }

    private func createWineBottle(runtime: RuntimeDescriptor, diagnostics: Bool) async throws {
        try FileManager.default.createDirectory(at: runtime.bottleRoot, withIntermediateDirectories: true)

        let result = try await processRunner.run(
            executable: runtime.wineExecutable,
            arguments: ["wineboot", "--init"],
            environment: runtimeManager.environment(for: runtime, diagnostics: diagnostics),
            currentDirectory: runtime.bottleRoot,
            logURL: paths.logsDirectory.appendingPathComponent("bottle-initialize.log")
        )
        guard result.terminationStatus == 0 else {
            throw ProcessRunnerError.nonZeroExit(result.terminationStatus, result.logURL)
        }
    }

    private func configureMacDisplay(runtime: RuntimeDescriptor, diagnostics: Bool) async throws {
        let values = [
            (key: "HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver", name: "RetinaMode", type: "REG_SZ", value: "Y"),
            (key: "HKEY_CURRENT_USER\\Control Panel\\Desktop", name: "LogPixels", type: "REG_DWORD", value: "216")
        ]
        let environment = runtimeManager.environment(for: runtime, diagnostics: diagnostics)
        let logURL = paths.logsDirectory.appendingPathComponent("bottle-display.log")

        for value in values {
            let result = try await processRunner.run(
                executable: runtime.wineExecutable,
                arguments: runtime.wineArguments(for: [
                    "reg", "add", value.key, "/v", value.name,
                    "/t", value.type, "/d", value.value, "/f"
                ]),
                environment: environment,
                currentDirectory: runtime.bottleRoot,
                logURL: logURL
            )
            guard result.terminationStatus == 0 else {
                throw ProcessRunnerError.nonZeroExit(result.terminationStatus, result.logURL)
            }
        }
    }
}
