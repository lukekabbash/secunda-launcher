import Foundation

private final class CaptureContractResult: @unchecked Sendable {
    private let lock = NSLock()
    private var passed = false

    func record(_ value: Bool) {
        lock.lock()
        passed = value
        lock.unlock()
    }

    func snapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return passed
    }
}

enum ProcessRunnerSelfCheck {
    static func appendLogsStayBounded() -> Bool {
        let completion = DispatchSemaphore(value: 0)
        let result = CaptureContractResult()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("secunda-process-log-self-check-\(UUID().uuidString)")
        let log = directory.appendingPathComponent("diagnostic.log")

        Task.detached {
            defer {
                try? FileManager.default.removeItem(at: directory)
                completion.signal()
            }
            do {
                let runner = ProcessRunner(maximumLogBytes: 1_024)
                let first = try await runner.run(
                    executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "/usr/bin/awk 'BEGIN { for (i = 0; i < 4096; i++) printf \"x\" }'"],
                    environment: [:],
                    logURL: log,
                    timeoutSeconds: 2
                )
                let firstData = try Data(contentsOf: log)
                if firstData.count != 1_024 {
                    let detail = "bounded-log-self-check first-before-rotate=\(firstData.count)\n"
                    try? FileHandle.standardError.write(contentsOf: Data(detail.utf8))
                }
                let second = try await runner.run(
                    executable: URL(fileURLWithPath: "/usr/bin/printf"),
                    arguments: ["new"],
                    environment: [:],
                    logURL: log,
                    timeoutSeconds: 2
                )
                let archive = directory.appendingPathComponent("diagnostic.previous.log")
                let secondData = try Data(contentsOf: log)
                let archiveData = try Data(contentsOf: archive)
                let secondText = String(data: secondData, encoding: .utf8) ?? ""
                let passed =
                    first.terminationStatus == 0
                        && second.terminationStatus == 0
                        && firstData == Data(repeating: 120, count: 1_024)
                        && secondText.hasPrefix("new")
                        && secondText.contains("[secunda-process-termination]")
                        && secondText.contains("reason=exit")
                        && secondText.contains("status=0")
                        && secondData.count <= 1_024
                        && archiveData.count == 1_024
                if !passed {
                    let detail = "bounded-log-self-check first=\(firstData.count) second=\(secondData.count) archive=\(archiveData.count) text=\(secondText)\n"
                    try? FileHandle.standardError.write(contentsOf: Data(detail.utf8))
                }
                result.record(passed)
            } catch {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
                let detail = "bounded-log-self-check error=\(error.localizedDescription) files=\(names.sorted())\n"
                try? FileHandle.standardError.write(contentsOf: Data(detail.utf8))
                result.record(false)
            }
        }

        guard completion.wait(timeout: .now() + 5) == .success else { return false }
        return result.snapshot()
    }

    static func captureCompletesWhenChildInheritsOutput() -> Bool {
        runCaptureContract(
            command: "/bin/sleep 2 & /usr/bin/printf capture-complete",
            expected: Data("capture-complete".utf8),
            maxOutputBytes: 1_024
        )
    }

    static func capturePreservesMultipleChunksInOrder() -> Bool {
        let expected = (0..<500)
            .map { String(format: "line-%04d\n", $0) }
            .joined()
        return runCaptureContract(
            command: "/bin/sleep 2 & /usr/bin/awk 'BEGIN { for (i = 0; i < 500; i++) printf \"line-%04d\\n\", i }'",
            expected: Data(expected.utf8),
            maxOutputBytes: 16_384
        )
    }

    private static func runCaptureContract(
        command: String,
        expected: Data,
        maxOutputBytes: Int
    ) -> Bool {
        let completion = DispatchSemaphore(value: 0)
        let result = CaptureContractResult()

        Task.detached {
            defer { completion.signal() }
            do {
                let captured = try await ProcessRunner().capture(
                    executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", command],
                    environment: [:],
                    maxOutputBytes: maxOutputBytes,
                    timeoutSeconds: 0.6
                )
                result.record(
                    captured.terminationStatus == 0
                        && captured.output == expected
                )
            } catch {
                result.record(false)
            }
        }

        guard completion.wait(timeout: .now() + 2) == .success else { return false }
        return result.snapshot()
    }
}
