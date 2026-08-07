import Foundation

struct ProcessResult: Sendable {
    let terminationStatus: Int32
    let logURL: URL
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(Int32, URL)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message): message
        case .nonZeroExit(let status, let logURL):
            "The process exited with status \(status). See \(logURL.path)."
        }
    }
}

final class ProcessRunner {
    private let lock = NSLock()
    private var activeProcesses: [Int32: Process] = [:]

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil,
        logURL: URL
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let process = try configuredProcess(
                    executable: executable,
                    arguments: arguments,
                    environment: environment,
                    currentDirectory: currentDirectory,
                    logURL: logURL
                )
                process.terminationHandler = { process in
                    continuation.resume(returning: ProcessResult(
                        terminationStatus: process.terminationStatus,
                        logURL: logURL
                    ))
                }
                try process.run()
            } catch {
                continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
            }
        }
    }

    @discardableResult
    func launch(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil,
        logURL: URL
    ) throws -> Int32 {
        let process = try configuredProcess(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            logURL: logURL
        )

        process.terminationHandler = { [weak self] process in
            self?.lock.lock()
            self?.activeProcesses.removeValue(forKey: process.processIdentifier)
            self?.lock.unlock()
        }
        try process.run()

        lock.lock()
        activeProcesses[process.processIdentifier] = process
        lock.unlock()
        return process.processIdentifier
    }

    private func configuredProcess(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL?,
        logURL: URL
    ) throws -> Process {
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = SourceRuntimePolicy.sanitizedEnvironment(
            base: ProcessInfo.processInfo.environment,
            overrides: environment
        )
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = handle
        process.standardError = handle
        return process
    }
}
