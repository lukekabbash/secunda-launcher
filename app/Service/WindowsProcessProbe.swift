import Foundation

enum WindowsHandoffState: Equatable, Sendable {
    case game
    case launcher
    case none
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

    var handoffState: WindowsHandoffState {
        if contains(WindowsProcessProbe.gameImageName) { return .game }
        if contains(WindowsProcessProbe.launcherImageName) { return .launcher }
        return .none
    }
}

final class WindowsProcessProbe {
    static let gameImageName = GameDescriptor.skyrimSE.gameImageName
    static let launcherImageName = GameDescriptor.skyrimSE.launcherImageName
    static let queryTimeoutSeconds: TimeInterval = 15

    private let processRunner: ProcessRunner
    private let runtimeManager: RuntimeManager

    init(processRunner: ProcessRunner, runtimeManager: RuntimeManager) {
        self.processRunner = processRunner
        self.runtimeManager = runtimeManager
    }

    func snapshot(
        runtime: RuntimeDescriptor,
        diagnostics: Bool
    ) async throws -> WindowsProcessSnapshot {
        var names = Set<String>()
        if try await isRunning(
            Self.gameImageName,
            runtime: runtime,
            diagnostics: diagnostics
        ) {
            names.insert(Self.gameImageName)
            return WindowsProcessSnapshot(imageNames: names)
        }
        if try await isRunning(
            Self.launcherImageName,
            runtime: runtime,
            diagnostics: diagnostics
        ) {
            names.insert(Self.launcherImageName)
        }
        return WindowsProcessSnapshot(imageNames: names)
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

    func waitForHandoff(
        runtime: RuntimeDescriptor,
        diagnostics: Bool,
        timeoutSeconds: TimeInterval
    ) async throws -> WindowsHandoffState {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        repeat {
            try Task.checkCancellation()
            let state = try await snapshot(runtime: runtime, diagnostics: diagnostics).handoffState
            if state != .none { return state }
            if Date() >= deadline { return .none }
            try await Task.sleep(for: .milliseconds(750))
        } while true
    }

    func waitForGame(
        runtime: RuntimeDescriptor,
        diagnostics: Bool,
        timeoutSeconds: TimeInterval
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        repeat {
            try Task.checkCancellation()
            if try await isRunning(
                Self.gameImageName,
                runtime: runtime,
                diagnostics: diagnostics
            ) {
                return true
            }
            if Date() >= deadline { return false }
            try await Task.sleep(for: .milliseconds(500))
        } while true
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
