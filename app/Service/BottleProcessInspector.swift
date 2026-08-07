import Darwin
import Foundation

/// One Windows process running inside Secunda's game space, as seen by the
/// host OS.
struct BottleProcess: Identifiable, Equatable, Sendable {
    let pid: Int32
    let ppid: Int32
    let command: String

    var id: Int32 { pid }
    /// Reparented to launchd: its wineserver is gone, so Wine's own
    /// shutdown machinery can no longer reach it.
    var isOrphaned: Bool { ppid == 1 }

    /// Short display name: the Windows image name when present, else the
    /// executable's basename.
    var displayName: String {
        let head = command.components(separatedBy: " ").first ?? command
        let unixName = head.components(separatedBy: "/").last ?? head
        let windowsName = unixName.components(separatedBy: "\\").last ?? unixName
        return windowsName.isEmpty ? command : windowsName
    }
}

/// Finds and force-kills game-space processes using host-OS facilities
/// only (`/bin/ps`, `proc_pidpath`, `kill`). Deliberately independent of
/// Wine's own IPC: this must keep working when wineserver is already dead
/// and processes are orphaned — the exact failure being handled.
final class BottleProcessInspector {
    private let processRunner: ProcessRunner

    init(processRunner: ProcessRunner) {
        self.processRunner = processRunner
    }

    /// Every process belonging to this runtime's game space: matched by
    /// bottle path in the command line, or by the process's real executable
    /// living inside the runtime (Wine rewrites argv of system workers like
    /// winedevice.exe to cosmetic Windows paths).
    func runningProcesses(runtime: RuntimeDescriptor) async throws -> [BottleProcess] {
        let result = try await processRunner.capture(
            executable: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,ppid=,command="],
            environment: [:],
            maxOutputBytes: 2_097_152,
            timeoutSeconds: 10
        )
        guard result.terminationStatus == 0,
              let output = String(data: result.output, encoding: .utf8)
        else {
            return []
        }
        let runtimeRoot = runtime.wineExecutable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL.path
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return Self.parse(psOutput: output).filter { process in
            guard process.pid != ownPID else { return false }
            return Self.matches(
                process,
                bottlePath: runtime.bottleRoot.resolvingSymlinksInPath().standardizedFileURL.path,
                executablePath: Self.executablePath(of: process.pid),
                runtimeRoot: runtimeRoot
            )
        }
    }

    /// The scan above, narrowed to one game's image names for the per-game
    /// sidebar action.
    func runningProcesses(
        for descriptor: GameDescriptor,
        runtime: RuntimeDescriptor
    ) async throws -> [BottleProcess] {
        try await runningProcesses(runtime: runtime).filter { process in
            Self.matchesImages(
                process.command,
                images: [descriptor.gameImageName, descriptor.launcherImageName]
            )
        }
    }

    /// SIGTERM first, a short grace period, then SIGKILL for survivors.
    /// Idempotent: killing an already-gone PID is a no-op.
    func forceKill(_ processes: [BottleProcess]) async {
        guard !processes.isEmpty else { return }
        for process in processes {
            Darwin.kill(process.pid, SIGTERM)
        }
        try? await Task.sleep(for: .seconds(2))
        for process in processes where Darwin.kill(process.pid, 0) == 0 {
            Darwin.kill(process.pid, SIGKILL)
        }
    }

    // MARK: - Pure helpers (contract-tested)

    static func parse(psOutput: String) -> [BottleProcess] {
        psOutput.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let fields = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3,
                  let pid = Int32(fields[0]),
                  let ppid = Int32(fields[1])
            else {
                return nil
            }
            return BottleProcess(pid: pid, ppid: ppid, command: String(fields[2]))
        }
    }

    static func matches(
        _ process: BottleProcess,
        bottlePath: String,
        executablePath: String?,
        runtimeRoot: String
    ) -> Bool {
        if process.command.contains(bottlePath + "/") { return true }
        if let executablePath {
            let resolved = URL(fileURLWithPath: executablePath)
                .resolvingSymlinksInPath().standardizedFileURL.path
            if resolved.hasPrefix(runtimeRoot + "/") { return true }
        }
        return false
    }

    static func matchesImages(_ command: String, images: [String]) -> Bool {
        let lowered = command.lowercased()
        return Set(images.map { $0.lowercased() }).contains { lowered.contains($0) }
    }

    /// The process's real on-disk executable, independent of what ps shows.
    static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
