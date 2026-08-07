import Darwin
import Foundation

struct ProcessResult: Sendable {
    let terminationStatus: Int32
    let logURL: URL
}

struct CapturedProcessResult: Sendable {
    let terminationStatus: Int32
    let output: Data
}

enum ProcessOutput: Equatable, Sendable {
    case append(URL)
    case discard
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)
    case nonZeroExit(Int32, URL)
    case timedOut(TimeInterval, URL)
    case captureTimedOut(TimeInterval)
    case captureTooLarge(Int)
    case captureReadFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message): message
        case .nonZeroExit(let status, let logURL):
            "The process exited with status \(status). See \(logURL.path)."
        case .timedOut(let seconds, let logURL):
            "The process did not finish within \(Int(seconds)) seconds. See \(logURL.path)."
        case .captureTimedOut(let seconds):
            "The process did not finish within \(Int(seconds)) seconds."
        case .captureTooLarge(let limit):
            "The process produced more than \(limit) bytes of output."
        case .captureReadFailed(let errorNumber):
            "Secunda could not read the process output (system error \(errorNumber))."
        }
    }
}

private final class ProcessRunCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved = false
    private var timeoutRequested = false

    func requestTimeout() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved else { return false }
        timeoutRequested = true
        return true
    }

    func resolve() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved else { return nil }
        resolved = true
        return timeoutRequested
    }
}

private struct ConfiguredProcess {
    let process: Process
    let ownedOutputHandle: FileHandle?

    func closeOutput() {
        try? ownedOutputHandle?.close()
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
        logURL: URL,
        timeoutSeconds: TimeInterval? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let completion = ProcessRunCompletion()
            do {
                let configured = try configuredProcess(
                    executable: executable,
                    arguments: arguments,
                    environment: environment,
                    currentDirectory: currentDirectory,
                    output: .append(logURL)
                )
                let process = configured.process
                process.terminationHandler = { process in
                    configured.closeOutput()
                    guard let timedOut = completion.resolve() else { return }
                    if timedOut {
                        continuation.resume(throwing: ProcessRunnerError.timedOut(
                            timeoutSeconds ?? 0,
                            logURL
                        ))
                    } else {
                        continuation.resume(returning: ProcessResult(
                            terminationStatus: process.terminationStatus,
                            logURL: logURL
                        ))
                    }
                }
                try process.run()
                scheduleTimeout(
                    seconds: timeoutSeconds,
                    process: process,
                    completion: completion
                ) {
                    configured.closeOutput()
                    continuation.resume(throwing: ProcessRunnerError.timedOut(
                        timeoutSeconds ?? 0,
                        logURL
                    ))
                }
            } catch {
                guard completion.resolve() != nil else { return }
                continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
            }
        }
    }

    func capture(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil,
        maxOutputBytes: Int = 65_536,
        timeoutSeconds: TimeInterval = 5
    ) async throws -> CapturedProcessResult {
        precondition(maxOutputBytes > 0)
        return try await withCheckedThrowingContinuation { continuation in
            let completion = ProcessRunCompletion()
            let pipe = Pipe()
            let reader = pipe.fileHandleForReading
            var boundedCapture: BoundedPipeCapture?
            do {
                let capture = try BoundedPipeCapture(reader: reader, limit: maxOutputBytes)
                boundedCapture = capture
                let process = try baseProcess(
                    executable: executable,
                    arguments: arguments,
                    environment: environment,
                    currentDirectory: currentDirectory
                )
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                process.terminationHandler = { process in
                    guard let timedOut = completion.resolve() else { return }
                    let result = capture.finish()
                    if timedOut {
                        continuation.resume(throwing: ProcessRunnerError.captureTimedOut(timeoutSeconds))
                    } else if let readError = result.readError {
                        continuation.resume(throwing: ProcessRunnerError.captureReadFailed(readError))
                    } else if result.overflowed {
                        continuation.resume(throwing: ProcessRunnerError.captureTooLarge(maxOutputBytes))
                    } else {
                        continuation.resume(returning: CapturedProcessResult(
                            terminationStatus: process.terminationStatus,
                            output: result.data
                        ))
                    }
                }
                capture.start()
                try process.run()
                try? pipe.fileHandleForWriting.close()

                scheduleTimeout(
                    seconds: timeoutSeconds,
                    process: process,
                    completion: completion
                ) {
                    _ = capture.finish()
                    continuation.resume(throwing: ProcessRunnerError.captureTimedOut(timeoutSeconds))
                }
            } catch {
                try? pipe.fileHandleForWriting.close()
                guard completion.resolve() != nil else { return }
                if let boundedCapture {
                    _ = boundedCapture.finish()
                } else {
                    try? reader.close()
                }
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
        try launch(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            output: .append(logURL)
        )
    }

    @discardableResult
    func launch(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil,
        output: ProcessOutput
    ) throws -> Int32 {
        let configured = try configuredProcess(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            output: output
        )
        let process = configured.process
        process.terminationHandler = { [weak self] process in
            configured.closeOutput()
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
        output: ProcessOutput
    ) throws -> ConfiguredProcess {
        let process = try baseProcess(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory
        )

        switch output {
        case .append(let logURL):
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            process.standardOutput = handle
            process.standardError = handle
            return ConfiguredProcess(process: process, ownedOutputHandle: handle)
        case .discard:
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            return ConfiguredProcess(process: process, ownedOutputHandle: nil)
        }
    }

    private func baseProcess(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL?
    ) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = SourceRuntimePolicy.sanitizedEnvironment(
            base: ProcessInfo.processInfo.environment,
            overrides: environment
        )
        process.currentDirectoryURL = currentDirectory
        return process
    }

    private func scheduleTimeout(
        seconds: TimeInterval?,
        process: Process,
        completion: ProcessRunCompletion,
        fallback: @escaping @Sendable () -> Void
    ) {
        guard let seconds else { return }
        let processID = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) {
            guard completion.requestTimeout() else { return }
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if process.isRunning {
                    Darwin.kill(processID, SIGKILL)
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                    guard completion.resolve() != nil else { return }
                    fallback()
                }
            }
        }
    }
}
