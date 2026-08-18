import Foundation

struct GameLaunchRecord: Codable, Equatable, Sendable {
    struct EngineLog: Codable, Equatable, Sendable {
        struct SourceState: Codable, Equatable, Sendable {
            let driver: String?
            let direct3DLevel: String?
            let videoMode: String?
            let verticalSync: String?
        }

        let relativePath: String
        let modifiedAt: String?
        let byteCount: Int?
        let sourceState: SourceState?
    }

    let recordType: String
    let attemptID: String
    let timestamp: String
    let gameID: String
    let steamAppID: String
    let arguments: [String]
    let displayMode: String
    let displayCoordinatePolicy: String
    let width: Int
    let height: Int
    let requestedDisplayMode: String?
    let requestedWidth: Int?
    let requestedHeight: Int?
    let screenPointWidth: Int
    let screenPointHeight: Int
    let screenPixelWidth: Int
    let screenPixelHeight: Int
    let backingScale: Double
    let logPixels: Int
    let retinaMode: Bool
    let d3d9Backend: String
    let sessionFingerprint: String?
    let engineLogBeforeLaunch: EngineLog?
}

struct GameLaunchRenderObservation: Codable, Equatable, Sendable {
    struct Window: Codable, Equatable, Sendable {
        let windowID: UInt32
        let ownerPID: Int32
        let isOnscreen: Bool
        let layer: Int
        let alpha: Double
        let x: Int
        let y: Int
        let width: Int
        let height: Int

        init(_ surface: GameWindowSurface) {
            windowID = surface.windowID
            ownerPID = surface.ownerPID
            isOnscreen = surface.isOnscreen
            layer = surface.layer
            alpha = surface.alpha
            x = surface.x
            y = surface.y
            width = surface.width
            height = surface.height
        }
    }

    let recordType: String
    let attemptID: String
    let timestamp: String
    let gameID: String
    let steamAppID: String
    let launchOutcome: String
    let window: Window?
    let frame: GameFrameObservation
    let engineLogAfterWindow: GameLaunchRecord.EngineLog?
}

/// Records a bounded, credential-free diagnostic timeline. Image pixels,
/// window titles, command environments, and full engine logs are never kept.
struct GameLaunchRecorder {
    static let fileName = "launch-records.jsonl"
    static let archiveFileName = "launch-records.previous.jsonl"
    static let maximumFileBytes = 1_048_576
    private static let frameOutcomeGameIDs: Set<String> = [
        "insurgency",
        "bo2-campaign",
        "bo2-multiplayer",
        "bo2-zombies"
    ]

    private let paths: SecundaPaths

    init(paths: SecundaPaths) {
        self.paths = paths
    }

    static func makeAttemptID(diagnostics: Bool) -> String? {
        diagnostics ? UUID().uuidString.lowercased() : nil
    }

    static func recordsFrameOutcome(for descriptor: GameDescriptor, diagnostics: Bool) -> Bool {
        diagnostics && frameOutcomeGameIDs.contains(descriptor.id)
    }

    func recordRequest(
        descriptor: GameDescriptor,
        settings: GameSettings,
        arguments: [String],
        logPixels: Int,
        retinaMode: Bool,
        bottleRoot: URL,
        installRoot: URL?,
        requestedSettings: GameSettings? = nil,
        displayGeometry: HostDisplayGeometry = .unknown,
        sessionFingerprint: String? = nil,
        attemptID: String? = nil,
        diagnostics: Bool
    ) {
        guard diagnostics, let attemptID else { return }
        let record = Self.makeRecord(
            descriptor: descriptor,
            settings: settings,
            arguments: arguments,
            logPixels: logPixels,
            retinaMode: retinaMode,
            bottleRoot: bottleRoot,
            installRoot: installRoot,
            requestedSettings: requestedSettings,
            displayGeometry: displayGeometry,
            sessionFingerprint: sessionFingerprint,
            attemptID: attemptID
        )
        append(record)
    }

    func recordFrameOutcome(
        descriptor: GameDescriptor,
        attemptID: String?,
        launchOutcome: GameLaunchOutcome?,
        surface: GameWindowSurface?,
        frame: GameFrameObservation,
        bottleRoot: URL,
        installRoot: URL?,
        diagnostics: Bool
    ) {
        guard Self.recordsFrameOutcome(for: descriptor, diagnostics: diagnostics),
              let attemptID
        else { return }
        let record = GameLaunchRenderObservation(
            recordType: "launch-render-observation",
            attemptID: attemptID,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            gameID: descriptor.id,
            steamAppID: descriptor.steamAppID,
            launchOutcome: Self.outcomeLabel(launchOutcome),
            window: surface.map(GameLaunchRenderObservation.Window.init),
            frame: frame,
            engineLogAfterWindow: Self.engineLog(
                descriptor: descriptor,
                bottleRoot: bottleRoot,
                installRoot: installRoot
            )
        )
        append(record)
    }

    static func makeRecord(
        descriptor: GameDescriptor,
        settings: GameSettings,
        arguments: [String],
        logPixels: Int,
        retinaMode: Bool,
        bottleRoot: URL,
        installRoot: URL?,
        requestedSettings: GameSettings? = nil,
        displayGeometry: HostDisplayGeometry = .unknown,
        sessionFingerprint: String? = nil,
        attemptID: String = "self-check",
        now: Date = Date()
    ) -> GameLaunchRecord {
        GameLaunchRecord(
            recordType: "launch-request",
            attemptID: attemptID,
            timestamp: ISO8601DateFormatter().string(from: now),
            gameID: descriptor.id,
            steamAppID: descriptor.steamAppID,
            arguments: arguments,
            displayMode: settings.displayMode.rawValue,
            displayCoordinatePolicy: descriptor.launchProfile.displayCoordinatePolicy.rawValue,
            width: settings.width,
            height: settings.height,
            requestedDisplayMode: requestedSettings?.displayMode.rawValue,
            requestedWidth: requestedSettings?.width,
            requestedHeight: requestedSettings?.height,
            screenPointWidth: displayGeometry.fullFramePoints.width,
            screenPointHeight: displayGeometry.fullFramePoints.height,
            screenPixelWidth: displayGeometry.fullFramePixels.width,
            screenPixelHeight: displayGeometry.fullFramePixels.height,
            backingScale: displayGeometry.backingScale,
            logPixels: logPixels,
            retinaMode: retinaMode,
            d3d9Backend: descriptor.d3d9Backend == .dxvk ? "dxvk" : "wined3d",
            sessionFingerprint: sessionFingerprint,
            engineLogBeforeLaunch: engineLog(
                descriptor: descriptor,
                bottleRoot: bottleRoot,
                installRoot: installRoot
            )
        )
    }

    static func insurgencyState(from contents: String) -> GameLaunchRecord.EngineLog.SourceState? {
        let state = GameLaunchRecord.EngineLog.SourceState(
            driver: fieldValue(in: contents, labels: ["driver:", "driver name:"]),
            direct3DLevel: fieldValue(in: contents, labels: ["dxlevel:"]),
            videoMode: fieldValue(in: contents, labels: ["vid:"]),
            verticalSync: fieldValue(in: contents, labels: ["vsync:"])
        )
        return state.driver == nil
            && state.direct3DLevel == nil
            && state.videoMode == nil
            && state.verticalSync == nil
            ? nil
            : state
    }

    private static func engineLog(
        descriptor: GameDescriptor,
        bottleRoot: URL,
        installRoot: URL?
    ) -> GameLaunchRecord.EngineLog? {
        let location: (relativePath: String, url: URL)?
        switch descriptor.id {
        case "supcom2":
            let relativePath = "drive_c/sc2.log"
            location = (relativePath, bottleRoot.appendingPathComponent(relativePath))
        case "angels-fall-first":
            let relativePath = "AFFGame/Logs/Launch.log"
            location = installRoot.map { (relativePath, $0.appendingPathComponent(relativePath)) }
        case "insurgency":
            let relativePath = "state_launch.txt"
            location = installRoot.map { (relativePath, $0.appendingPathComponent(relativePath)) }
        default:
            location = nil
        }
        guard let location else { return nil }
        let values = try? location.url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ])
        let contents = try? String(contentsOf: location.url, encoding: .utf8)
        return GameLaunchRecord.EngineLog(
            relativePath: location.relativePath,
            modifiedAt: values?.contentModificationDate.map {
                ISO8601DateFormatter().string(from: $0)
            },
            byteCount: values?.fileSize,
            sourceState: descriptor.id == "insurgency"
                ? contents.flatMap(Self.insurgencyState)
                : nil
        )
    }

    private static func fieldValue(in contents: String, labels: [String]) -> String? {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line.lowercased()
            for label in labels where lowercased.hasPrefix(label) {
                let value = line.dropFirst(label.count).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                return String(value.prefix(160))
            }
        }
        return nil
    }

    private static func outcomeLabel(_ outcome: GameLaunchOutcome?) -> String {
        switch outcome {
        case .started: "started"
        case .alreadyRunning: "already-running"
        case nil: "window-not-visible"
        }
    }

    private func append<T: Encodable>(_ record: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record) else { return }
        append(data + Data([0x0a]))
    }

    private func append(_ data: Data) {
        let url = paths.logsDirectory.appendingPathComponent(Self.fileName)
        do {
            try FileManager.default.createDirectory(
                at: paths.logsDirectory,
                withIntermediateDirectories: true
            )
            try rotateIfNeeded(url: url, incomingBytes: data.count)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Diagnostics must never become a game-launch failure.
        }
    }

    private func rotateIfNeeded(url: URL, incomingBytes: Int) throws {
        let currentSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard currentSize + incomingBytes > Self.maximumFileBytes,
              FileManager.default.fileExists(atPath: url.path)
        else { return }

        let archive = paths.logsDirectory.appendingPathComponent(Self.archiveFileName)
        if FileManager.default.fileExists(atPath: archive.path) {
            try FileManager.default.removeItem(at: archive)
        }
        try FileManager.default.moveItem(at: url, to: archive)
    }
}
