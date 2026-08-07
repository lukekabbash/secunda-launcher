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
