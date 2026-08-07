import Foundation

struct HostPowerProbe {
    private let processRunner: ProcessRunner

    init(processRunner: ProcessRunner) {
        self.processRunner = processRunner
    }

    func lowPowerModeEnabled() async -> Bool? {
        guard let result = try? await processRunner.capture(
            executable: URL(fileURLWithPath: "/usr/bin/pmset"),
            arguments: ["-g"],
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            maxOutputBytes: 16_384,
            timeoutSeconds: 3
        ), result.terminationStatus == 0 else {
            return nil
        }
        return Self.lowPowerModeEnabled(in: result.output)
    }

    static func lowPowerModeEnabled(in output: Data) -> Bool? {
        guard let text = String(data: output, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let fields = line.split(whereSeparator: \Character.isWhitespace)
            guard fields.count == 2, fields[0] == "lowpowermode" else { continue }
            if fields[1] == "1" { return true }
            if fields[1] == "0" { return false }
            return nil
        }
        return nil
    }
}
