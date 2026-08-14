import Foundation

struct ExecutableDisplayPolicy: Equatable, Sendable {
    let application: String
    let decorated: Bool
    let capturesDisplaysForFullscreen: Bool
}

final class BottleManager {
    static let gameDLLOverrides = [
        "x3daudio1_6",
        "x3daudio1_7",
        "xaudio2_6",
        "xaudio2_7"
    ]
    static let gracefulShutdownArguments = [
        "wineboot",
        "--end-session",
        "--shutdown"
    ]
    static let forcedShutdownArguments = ["wineboot", "--kill", "--shutdown"]
    static let initializationWaitArguments = ["-w"]

    /// Build an app-scoped Mac-driver decoration override. Keeping this
    /// separate from the shared registry values prevents a fullscreen fix for
    /// one game from changing Steam or another game in the bottle.
    static func appMacDriverDecoration(
        application: String,
        decorated: Bool
    ) -> (key: String, name: String, type: String, value: String)? {
        guard !application.isEmpty,
              !application.contains("\\"),
              !application.contains("/")
        else { return nil }
        return (
            key: "HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(application)\\Mac Driver",
            name: "Decorated",
            type: "REG_SZ",
            value: decorated ? "Y" : "N"
        )
    }

    /// Emit only executable-scoped window policy. The X11 key owns Win32
    /// decoration; the Mac key owns physical display capture.
    static func appDisplayPolicyValues(
        _ policy: ExecutableDisplayPolicy
    ) -> [(key: String, name: String, type: String, value: String)] {
        let application = policy.application
        guard !application.isEmpty,
              !application.contains("\\"),
              !application.contains("/")
        else { return [] }
        let appKey = "HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(application)"
        return [
            (
                key: "\(appKey)\\X11 Driver",
                name: "Decorated",
                type: "REG_SZ",
                value: policy.decorated ? "Y" : "N"
            ),
            (
                key: "\(appKey)\\Mac Driver",
                name: "CaptureDisplaysForFullscreen",
                type: "REG_SZ",
                value: policy.capturesDisplaysForFullscreen ? "Y" : "N"
            )
        ]
    }

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
        return paths.isManagedBottleRoot(bottleRoot)
            && hasWinePrefix(at: bottleRoot)
            && Self.hasPrivateDocuments(paths: paths, bottleRoot: bottleRoot)
    }

    func initialize(runtime: RuntimeDescriptor, diagnostics: Bool) async throws {
        guard paths.isManagedBottleRoot(runtime.bottleRoot) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try paths.prepareManagedDirectories()

        let isNewPrefix = !hasWinePrefix(at: runtime.bottleRoot)
        if isNewPrefix {
            try await createWineBottle(runtime: runtime, diagnostics: diagnostics)
        }

        try Self.preparePrivateDocuments(paths: paths, bottleRoot: runtime.bottleRoot)
        // Existing prefixes may be carrying a deliberate per-game native-DPI
        // contract. Reinitialization must not race that launch and put Retina
        // cursor scaling back underneath a point-space game window.
        if isNewPrefix {
            try await configureMacDisplay(runtime: runtime, diagnostics: diagnostics)
        }
    }

    func applyGameCompatibility(
        runtime: RuntimeDescriptor,
        diagnostics: Bool,
        logPixels: Int = GameProfileWriter.standardLogPixels,
        retinaMode: Bool = true,
        nativeVoiceAudio: Bool = false,
        d3d9Backend: D3D9Backend = .wined3d,
        /// Optional per-executable Mac-driver decoration override. Keeping
        /// this app-scoped avoids changing Steam or unrelated game windows in
        /// the shared bottle.
        macDriverApplication: String? = nil,
        macDriverDecorated: Bool? = nil,
        executableDisplayPolicies: [ExecutableDisplayPolicy] = [],
        environment: [String: String]? = nil
    ) async throws {
        let effectiveEnvironment = environment
            ?? runtimeManager.environment(for: runtime, diagnostics: diagnostics)
        let logURL = paths.logsDirectory.appendingPathComponent("game-compatibility.log")

        // The runtime has no WMA decode path, so xWMA voice lines are silent
        // through the builtin XAudio. When Microsoft's freely redistributable
        // XAudio 2.7 has been installed into the game space, prefer it.
        var overrides = Dictionary(uniqueKeysWithValues: Self.gameDLLOverrides.map { ($0, "builtin") })
        if nativeVoiceAudio {
            for name in VoiceAudioService.nativeDLLBaseNames {
                overrides[name] = "native,builtin"
            }
        }

        // Per-session Direct3D 9 backend: DXVK games load the native DXVK
        // d3d9.dll installed in the prefix; everyone else keeps the builtin
        // wined3d path. Vulkan availability is global, so the GL renderer is
        // pinned to keep wined3d behavior identical either way.
        overrides["d3d9"] = d3d9Backend == .dxvk ? "native,builtin" : "builtin"

        for (name, value) in overrides.sorted(by: { $0.key < $1.key }) {
            let result = try await processRunner.run(
                executable: runtime.wineExecutable,
                arguments: runtime.wineArguments(for: [
                    "reg", "add", "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides",
                    "/v", name, "/t", "REG_SZ", "/d", value, "/f"
                ]),
                environment: effectiveEnvironment,
                currentDirectory: runtime.bottleRoot,
                logURL: logURL
            )
            guard result.terminationStatus == 0 else {
                throw ProcessRunnerError.nonZeroExit(result.terminationStatus, result.logURL)
            }
        }

        // Session DPI: 216 keeps Steam legible on Retina panels; 96 gives a
        // native-resolution game session exact 1:1 pixel mapping. The GL pin
        // keeps wined3d off its Vulkan backend now that MoltenVK is present.
        // Retina mode goes with the DPI: win32 metrics report pixel-doubled
        // geometry under it, but DXMT enumerates display modes through
        // CoreGraphics in points — a maximized window and the game's mode
        // list end up in different coordinate spaces and the image lands in
        // a corner of the window. Native-DPI sessions drop to point space
        // everywhere so window, desktop, and mode list agree.
        let registryValues: [(key: String, name: String, type: String, value: String)] = [
            (
                key: "HKEY_CURRENT_USER\\Control Panel\\Desktop",
                name: "LogPixels", type: "REG_DWORD", value: String(logPixels)
            ),
            (
                key: "HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver",
                name: "RetinaMode", type: "REG_SZ", value: retinaMode ? "Y" : "N"
            ),
            (
                key: "HKEY_CURRENT_USER\\Software\\Wine\\Direct3D",
                name: "renderer", type: "REG_SZ", value: "gl"
            )
        ]
        var sessionRegistryValues = registryValues
        if let macDriverApplication,
           let macDriverDecorated,
           let decoration = Self.appMacDriverDecoration(
               application: macDriverApplication,
               decorated: macDriverDecorated
           ) {
            sessionRegistryValues.append(decoration)
        }
        for executableDisplayPolicy in executableDisplayPolicies {
            sessionRegistryValues.append(
                contentsOf: Self.appDisplayPolicyValues(executableDisplayPolicy)
            )
        }
        for entry in sessionRegistryValues {
            let result = try await processRunner.run(
                executable: runtime.wineExecutable,
                arguments: runtime.wineArguments(for: [
                    "reg", "add", entry.key,
                    "/v", entry.name, "/t", entry.type, "/d", entry.value, "/f"
                ]),
                environment: effectiveEnvironment,
                currentDirectory: runtime.bottleRoot,
                logURL: logURL
            )
            guard result.terminationStatus == 0 else {
                throw ProcessRunnerError.nonZeroExit(result.terminationStatus, result.logURL)
            }
        }
    }

    func shutdown(runtime: RuntimeDescriptor, diagnostics: Bool) async throws {
        let environment = runtimeManager.environment(for: runtime, diagnostics: diagnostics)
        _ = try? await processRunner.run(
            executable: runtime.wineExecutable,
            arguments: runtime.wineArguments(for: Self.gracefulShutdownArguments),
            environment: environment,
            currentDirectory: runtime.bottleRoot,
            logURL: paths.logsDirectory.appendingPathComponent("bottle-shutdown-graceful.log"),
            timeoutSeconds: 8
        )

        let forcedResult = try await processRunner.run(
            executable: runtime.wineExecutable,
            arguments: runtime.wineArguments(for: Self.forcedShutdownArguments),
            environment: environment,
            currentDirectory: runtime.bottleRoot,
            logURL: paths.logsDirectory.appendingPathComponent("bottle-shutdown-final.log"),
            timeoutSeconds: 10
        )
        guard forcedResult.terminationStatus == 0 else {
            throw ProcessRunnerError.nonZeroExit(
                forcedResult.terminationStatus,
                forcedResult.logURL
            )
        }

        let wineserver = runtime.wineExecutable
            .deletingLastPathComponent()
            .appendingPathComponent("wineserver")
        let waitResult = try await processRunner.run(
            executable: wineserver,
            arguments: ["-w"],
            environment: environment,
            currentDirectory: runtime.bottleRoot,
            logURL: paths.logsDirectory.appendingPathComponent("bottle-shutdown-wait.log"),
            timeoutSeconds: 10
        )
        guard waitResult.terminationStatus == 0 else {
            throw ProcessRunnerError.nonZeroExit(waitResult.terminationStatus, waitResult.logURL)
        }
    }

    /// Best-effort `wineserver -k` after an OS-level force kill, so a
    /// half-alive wineserver doesn't linger. Failure is acceptable — the
    /// processes are already dead.
    @discardableResult
    func requestWineserverExit(
        wineserver: URL,
        runtime: RuntimeDescriptor,
        diagnostics: Bool
    ) async throws -> Int32 {
        let result = try await processRunner.run(
            executable: wineserver,
            arguments: ["-k"],
            environment: runtimeManager.environment(for: runtime, diagnostics: diagnostics),
            currentDirectory: runtime.bottleRoot,
            logURL: paths.logsDirectory.appendingPathComponent("bottle-force-stop.log"),
            timeoutSeconds: 8
        )
        return result.terminationStatus
    }

    static func hasPrivateDocuments(paths: SecundaPaths, bottleRoot: URL) -> Bool {
        guard paths.isManagedBottleRoot(bottleRoot) else { return false }
        let userDirectory = paths.activeWindowsUserDirectory(in: bottleRoot)
        guard isContained(userDirectory, in: bottleRoot), !isSymbolicLink(userDirectory) else {
            return false
        }
        let documents = userDirectory
            .appendingPathComponent("Documents", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: documents.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              !isSymbolicLink(documents)
        else {
            return false
        }

        let resolvedBottle = bottleRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedDocuments = documents.resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedDocuments.hasPrefix(resolvedBottle + "/")
    }

    static func preparePrivateDocuments(paths: SecundaPaths, bottleRoot: URL) throws {
        guard paths.isManagedBottleRoot(bottleRoot) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let userDirectory = paths.activeWindowsUserDirectory(in: bottleRoot)
        guard isContained(userDirectory, in: bottleRoot), !isSymbolicLink(userDirectory) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let documents = userDirectory
            .appendingPathComponent("Documents", isDirectory: true)
        let manager = FileManager.default

        if isSymbolicLink(documents) {
            try manager.removeItem(at: documents)
        }
        try manager.createDirectory(at: documents, withIntermediateDirectories: true)

        guard hasPrivateDocuments(paths: paths, bottleRoot: bottleRoot) else {
            throw CocoaError(.fileWriteNoPermission)
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
        try await waitForWineInitialization(runtime: runtime, diagnostics: diagnostics)
    }

    private func waitForWineInitialization(
        runtime: RuntimeDescriptor,
        diagnostics: Bool
    ) async throws {
        let wineserver = runtime.wineExecutable
            .deletingLastPathComponent()
            .appendingPathComponent("wineserver")
        let result = try await processRunner.run(
            executable: wineserver,
            arguments: Self.initializationWaitArguments,
            environment: runtimeManager.environment(for: runtime, diagnostics: diagnostics),
            currentDirectory: runtime.bottleRoot,
            logURL: paths.logsDirectory.appendingPathComponent("bottle-initialize-wait.log"),
            timeoutSeconds: 30
        )
        guard result.terminationStatus == 0 else {
            throw ProcessRunnerError.nonZeroExit(result.terminationStatus, result.logURL)
        }
    }

    private func hasWinePrefix(at bottleRoot: URL) -> Bool {
        FileManager.default.fileExists(atPath: bottleRoot.appendingPathComponent("system.reg").path)
            && FileManager.default.fileExists(atPath: bottleRoot.appendingPathComponent("drive_c").path)
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true
    }

    private static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        return resolvedCandidate.hasPrefix(resolvedRoot + "/")
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
