import Foundation

enum VoiceAudioError: LocalizedError {
    case downloadFailed
    case extractionFailed(String)
    case installIncomplete

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            "Secunda could not download the Microsoft XAudio installer. Check the network connection and try again."
        case .extractionFailed(let step):
            "Secunda could not unpack the Microsoft XAudio components (\(step))."
        case .installIncomplete:
            "The Microsoft XAudio components did not install completely."
        }
    }
}

/// Installs Microsoft's freely redistributable XAudio 2.7 into the managed
/// game space so xWMA-compressed dialogue decodes. The source-built runtime
/// carries no WMA decoder (no GStreamer), so Wine's builtin XAudio plays
/// voice lines as silence. Nothing here is bundled into Secunda: the
/// DirectX runtime is fetched from Microsoft at the player's request, the
/// same trust model as installing Steam from Valve.
final class VoiceAudioService {
    static let redistributableURL = URL(
        string: "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe"
    )!
    /// DLL override base names that switch to native when installed.
    static let nativeDLLBaseNames = ["x3daudio1_7", "xactengine3_7", "xaudio2_7"]
    /// 64-bit payload files the game loads, and the cabinets that carry them.
    static let requiredFiles: [(cabinet: String, file: String)] = [
        (cabinet: "Jun2010_XAudio_x64.cab", file: "XAudio2_7.dll"),
        (cabinet: "Feb2010_X3DAudio_x64.cab", file: "X3DAudio1_7.dll"),
        (cabinet: "Jun2010_XACT_x64.cab", file: "xactengine3_7.dll")
    ]

    private let paths: SecundaPaths
    private let processRunner: ProcessRunner
    private let runtimeManager: RuntimeManager

    init(paths: SecundaPaths, processRunner: ProcessRunner, runtimeManager: RuntimeManager) {
        self.paths = paths
        self.processRunner = processRunner
        self.runtimeManager = runtimeManager
    }

    /// Readiness requires a complete, structurally valid x64 DLL set, not just
    /// the absence of Wine's placeholder marker. This is not publisher verification.
    func isInstalled(bottleRoot: URL) -> Bool {
        Self.requiredFiles.allSatisfy { entry in
            let url = system32Directory(in: bottleRoot).appendingPathComponent(entry.file)
            return NativeAudioPayload.validatedContents(at: url) != nil
        }
    }

    static func isWinePlaceholder(_ data: Data) -> Bool {
        data.range(of: Data("Wine placeholder DLL".utf8)) != nil
    }

    func installIfNeeded(runtime: RuntimeDescriptor, diagnostics: Bool) async throws {
        guard !isInstalled(bottleRoot: runtime.bottleRoot) else { return }
        guard paths.isManagedBottleRoot(runtime.bottleRoot) else {
            throw CocoaError(.fileWriteNoPermission)
        }

        let redistributable = try await downloadRedistributable()
        let stage = runtime.bottleRoot.appendingPathComponent(
            "drive_c/secunda-xaudio-stage",
            isDirectory: true
        )
        let manager = FileManager.default
        try? manager.removeItem(at: stage)
        try manager.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: stage) }

        // Step 1: the outer self-extracting installer unpacks its cabinets.
        let environment = runtimeManager.environment(for: runtime, diagnostics: diagnostics)
        let logURL = paths.logsDirectory.appendingPathComponent("voice-audio-install.log")
        let unpack = try await processRunner.run(
            executable: runtime.wineExecutable,
            arguments: runtime.wineArguments(for: [
                redistributable.path, "/Q", "/T:C:\\secunda-xaudio-stage"
            ]),
            environment: environment,
            currentDirectory: runtime.bottleRoot,
            logURL: logURL,
            timeoutSeconds: 300
        )
        guard unpack.terminationStatus == 0 else {
            throw VoiceAudioError.extractionFailed("installer unpack")
        }

        let payloadDirectory = stage.appendingPathComponent("payload", isDirectory: true)
        try manager.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)

        // Step 2: expand into staging, never directly over the live DLL set.
        // Wine's expand uses the two-argument `infile outfile` form; each cabinet
        // carries exactly the one DLL we need.
        for entry in Self.requiredFiles {
            let cabinet = stage.appendingPathComponent(entry.cabinet)
            guard manager.fileExists(atPath: cabinet.path) else {
                throw VoiceAudioError.extractionFailed(entry.cabinet)
            }
            let expand = try await processRunner.run(
                executable: runtime.wineExecutable,
                arguments: runtime.wineArguments(for: [
                    "expand",
                    "C:\\secunda-xaudio-stage\\\(entry.cabinet)",
                    "C:\\secunda-xaudio-stage\\payload\\\(entry.file)"
                ]),
                environment: environment,
                currentDirectory: runtime.bottleRoot,
                logURL: logURL,
                timeoutSeconds: 120
            )
            guard expand.terminationStatus == 0 else {
                throw VoiceAudioError.extractionFailed(entry.file)
            }
        }

        // Validate every payload before replacing any live file. Atomic writes
        // prevent a single DLL being left truncated. A failed/partial commit throws;
        // it never enables overrides, and the next attempt validates the set again.
        let payloads = try Self.requiredFiles.map { entry -> (String, Data) in
            guard let data = NativeAudioPayload.validatedContents(
                at: payloadDirectory.appendingPathComponent(entry.file)
            ) else { throw VoiceAudioError.installIncomplete }
            return (entry.file, data)
        }
        for (name, data) in payloads {
            try data.write(
                to: system32Directory(in: runtime.bottleRoot).appendingPathComponent(name),
                options: .atomic
            )
        }
        guard isInstalled(bottleRoot: runtime.bottleRoot) else {
            throw VoiceAudioError.installIncomplete
        }
    }

    private func downloadRedistributable() async throws -> URL {
        try paths.prepareManagedDirectories()
        let destination = paths.downloadsDirectory.appendingPathComponent("directx_Jun2010_redist.exe")
        // The redistributable is ~96 MB; treat a short file as a failed fetch.
        let minimumBytes = 90_000_000
        if let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > minimumBytes {
            return destination
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: Self.redistributableURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let size = try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > minimumBytes
        else {
            throw VoiceAudioError.downloadFailed
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func system32Directory(in bottleRoot: URL) -> URL {
        bottleRoot.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
    }
}
