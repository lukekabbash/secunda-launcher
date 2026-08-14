import Foundation

enum WindowsHandoffState: Equatable, Sendable {
    case game
    case launcher
    case gameExited
    case none
}

enum ProcessStabilityState: Equatable, Sendable {
    case absent
    case starting
    case stable
    case exited
}

/// Small launch-health state machine. A process is not considered launched
/// merely because one tasklist sample caught it during initialization.
struct ProcessStabilityTracker: Sendable {
    let requiredStableSeconds: TimeInterval
    private(set) var wasSeen = false
    private var firstSeenAt: Date?

    init(requiredStableSeconds: TimeInterval) {
        precondition(requiredStableSeconds >= 0)
        self.requiredStableSeconds = requiredStableSeconds
    }

    mutating func observe(isRunning: Bool, at date: Date) -> ProcessStabilityState {
        guard isRunning else {
            // Stability is continuous. A later process with the same image
            // starts a new health window instead of inheriting this lifetime.
            firstSeenAt = nil
            return wasSeen ? .exited : .absent
        }
        wasSeen = true
        if firstSeenAt == nil { firstSeenAt = date }
        guard let firstSeenAt else { return .starting }
        return date.timeIntervalSince(firstSeenAt) >= requiredStableSeconds ? .stable : .starting
    }
}

enum WindowsProcessProbeError: LocalizedError {
    case commandFailed(Int32)
    case malformedOutput

    var errorDescription: String? {
        switch self {
        case .commandFailed(let status):
            "Secunda could not inspect its Windows game space (status \(status))."
        case .malformedOutput:
            "Secunda received an invalid Windows process snapshot."
        }
    }
}

struct WindowsProcessSnapshot: Equatable, Sendable {
    fileprivate let imageNames: Set<String>

    init(imageNames: Set<String>) {
        self.imageNames = Set(imageNames.map { $0.lowercased() })
    }

    func contains(_ imageName: String) -> Bool {
        imageNames.contains(imageName.lowercased())
    }

    func containsAny(_ candidates: [String]) -> Bool {
        candidates.contains(where: contains)
    }

    var handoffState: WindowsHandoffState {
        handoffState(
            gameImage: WindowsProcessProbe.gameImageName,
            launcherImage: WindowsProcessProbe.launcherImageName
        )
    }

    func handoffState(gameImage: String, launcherImage: String) -> WindowsHandoffState {
        handoffState(gameImages: [gameImage], launcherImages: [launcherImage])
    }

    func handoffState(gameImages: [String], launcherImages: [String]) -> WindowsHandoffState {
        if containsAny(gameImages) { return .game }
        if containsAny(launcherImages) { return .launcher }
        return .none
    }
}

final class WindowsProcessProbe {
    static let gameImageName = GameDescriptor.skyrimSE.gameImageName
    static let launcherImageName = GameDescriptor.skyrimSE.launcherImageName
    static let queryTimeoutSeconds: TimeInterval = 15
    static let requiredStableGameSeconds: TimeInterval = 10

    private let processRunner: ProcessRunner
    private let runtimeManager: RuntimeManager

    init(processRunner: ProcessRunner, runtimeManager: RuntimeManager) {
        self.processRunner = processRunner
        self.runtimeManager = runtimeManager
    }

    func snapshot(
        runtime: RuntimeDescriptor,
        diagnostics: Bool,
        gameImages: [String],
        launcherImages: [String]
    ) async throws -> WindowsProcessSnapshot {
        var names = Set<String>()
        var seen = Set<String>()
        for image in gameImages + launcherImages
        where seen.insert(image.lowercased()).inserted {
            if try await isRunning(
                image,
                runtime: runtime,
                diagnostics: diagnostics
            ) {
                names.insert(image)
            }
        }
        return WindowsProcessSnapshot(imageNames: names)
    }

    func snapshot(
        runtime: RuntimeDescriptor,
        diagnostics: Bool,
        gameImage: String = WindowsProcessProbe.gameImageName,
        launcherImage: String = WindowsProcessProbe.launcherImageName
    ) async throws -> WindowsProcessSnapshot {
        try await snapshot(
            runtime: runtime,
            diagnostics: diagnostics,
            gameImages: [gameImage],
            launcherImages: [launcherImage]
        )
    }

    private func isRunning(
        _ imageName: String,
        runtime: RuntimeDescriptor,
        diagnostics: Bool
    ) async throws -> Bool {
        let result = try await processRunner.capture(
            executable: runtime.wineExecutable,
            arguments: runtime.wineArguments(for: [
                "tasklist",
                "/FI", "IMAGENAME eq \(imageName)",
                "/FO", "CSV",
                "/NH"
            ]),
            environment: runtimeManager.environment(for: runtime, diagnostics: diagnostics),
            currentDirectory: runtime.bottleRoot,
            maxOutputBytes: 8_192,
            timeoutSeconds: Self.queryTimeoutSeconds
        )
        guard result.terminationStatus == 0 else {
            throw WindowsProcessProbeError.commandFailed(result.terminationStatus)
        }
        guard let isPresent = Self.filteredImageIsPresent(imageName, in: result.output) else {
            throw WindowsProcessProbeError.malformedOutput
        }
        return isPresent
    }

    static func isTransientQueryTimeout(_ error: Error) -> Bool {
        guard case ProcessRunnerError.captureTimedOut = error else { return false }
        return true
    }

    func waitForHandoff(
        runtime: RuntimeDescriptor,
        diagnostics: Bool,
        timeoutSeconds: TimeInterval,
        gameImages: [String],
        launcherImages: [String],
        requiredStableSeconds: TimeInterval = WindowsProcessProbe.requiredStableGameSeconds
    ) async throws -> WindowsHandoffState {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var stability = Dictionary(uniqueKeysWithValues: gameImages.map {
            ($0.lowercased(), ProcessStabilityTracker(requiredStableSeconds: requiredStableSeconds))
        })
        var anyGameWasSeen = false
        var lastGameSeenAt: Date?
        repeat {
            try Task.checkCancellation()
            let processSnapshot: WindowsProcessSnapshot
            do {
                processSnapshot = try await snapshot(
                    runtime: runtime,
                    diagnostics: diagnostics,
                    gameImages: gameImages,
                    launcherImages: launcherImages
                )
            } catch where Self.isTransientQueryTimeout(error) {
                if Date() >= deadline {
                    return anyGameWasSeen ? .gameExited : .none
                }
                try await Task.sleep(for: .milliseconds(500))
                continue
            }
            let now = Date()
            var hasRunningGame = false
            for image in gameImages {
                let key = image.lowercased()
                guard var tracker = stability[key] else { continue }
                let isRunning = processSnapshot.contains(image)
                if isRunning {
                    hasRunningGame = true
                    anyGameWasSeen = true
                    lastGameSeenAt = now
                }
                if tracker.observe(isRunning: isRunning, at: now) == .stable {
                    return .game
                }
                stability[key] = tracker
            }
            if processSnapshot.containsAny(launcherImages) { return .launcher }
            // Architecture selectors can briefly disappear before the final
            // image appears. Do not combine their lifetimes or fail the first
            // candidate the instant it hands off to another.
            if anyGameWasSeen,
               !hasRunningGame,
               let lastGameSeenAt,
               now.timeIntervalSince(lastGameSeenAt) >= 2.25 {
                return .gameExited
            }
            if now >= deadline { return anyGameWasSeen ? .gameExited : .none }
            try await Task.sleep(for: .milliseconds(750))
        } while true
    }

    func waitForHandoff(
        runtime: RuntimeDescriptor,
        diagnostics: Bool,
        timeoutSeconds: TimeInterval,
        gameImage: String = WindowsProcessProbe.gameImageName,
        launcherImage: String = WindowsProcessProbe.launcherImageName,
        requiredStableSeconds: TimeInterval = WindowsProcessProbe.requiredStableGameSeconds
    ) async throws -> WindowsHandoffState {
        try await waitForHandoff(
            runtime: runtime,
            diagnostics: diagnostics,
            timeoutSeconds: timeoutSeconds,
            gameImages: [gameImage],
            launcherImages: [launcherImage],
            requiredStableSeconds: requiredStableSeconds
        )
    }

    func waitForGame(
        runtime: RuntimeDescriptor,
        diagnostics: Bool,
        timeoutSeconds: TimeInterval,
        gameImages: [String]
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var stability = Dictionary(uniqueKeysWithValues: gameImages.map {
            ($0.lowercased(), ProcessStabilityTracker(requiredStableSeconds: Self.requiredStableGameSeconds))
        })
        var anyGameWasSeen = false
        var lastGameSeenAt: Date?
        repeat {
            try Task.checkCancellation()
            let processSnapshot: WindowsProcessSnapshot
            do {
                processSnapshot = try await snapshot(
                    runtime: runtime,
                    diagnostics: diagnostics,
                    gameImages: gameImages,
                    launcherImages: []
                )
            } catch where Self.isTransientQueryTimeout(error) {
                if Date() >= deadline { return false }
                try await Task.sleep(for: .milliseconds(500))
                continue
            }
            let now = Date()
            var hasRunningGame = false
            for image in gameImages {
                let key = image.lowercased()
                guard var tracker = stability[key] else { continue }
                let isRunning = processSnapshot.contains(image)
                if isRunning {
                    hasRunningGame = true
                    anyGameWasSeen = true
                    lastGameSeenAt = now
                }
                if tracker.observe(isRunning: isRunning, at: now) == .stable {
                    return true
                }
                stability[key] = tracker
            }
            if anyGameWasSeen,
               !hasRunningGame,
               let lastGameSeenAt,
               now.timeIntervalSince(lastGameSeenAt) >= 2.25 {
                return false
            }
            if now >= deadline { return false }
            try await Task.sleep(for: .milliseconds(500))
        } while true
    }

    func waitForGame(
        runtime: RuntimeDescriptor,
        diagnostics: Bool,
        timeoutSeconds: TimeInterval,
        gameImage: String = WindowsProcessProbe.gameImageName
    ) async throws -> Bool {
        try await waitForGame(
            runtime: runtime,
            diagnostics: diagnostics,
            timeoutSeconds: timeoutSeconds,
            gameImages: [gameImage]
        )
    }

    static func imageNames(from output: Data) -> Set<String>? {
        guard let text = String(data: output, encoding: .utf8) else { return nil }
        var names = Set<String>()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let name = firstCSVField(in: line), !name.isEmpty else { return nil }
            names.insert(name.lowercased())
        }
        return names
    }

    static func filteredImageIsPresent(_ imageName: String, in output: Data) -> Bool? {
        guard let names = imageNames(from: output) else { return nil }
        guard names.count <= 1 else { return nil }
        guard let returnedName = names.first else { return false }
        return returnedName.caseInsensitiveCompare(imageName) == .orderedSame ? true : nil
    }

    private static func firstCSVField(in line: String) -> String? {
        guard line.first == "\"" else { return nil }
        var value = ""
        var index = line.index(after: line.startIndex)

        while index < line.endIndex {
            let character = line[index]
            guard character == "\"" else {
                value.append(character)
                index = line.index(after: index)
                continue
            }

            let next = line.index(after: index)
            if next < line.endIndex, line[next] == "\"" {
                value.append("\"")
                index = line.index(after: next)
                continue
            }
            guard next == line.endIndex || line[next] == "," else { return nil }
            return value
        }
        return nil
    }
}
