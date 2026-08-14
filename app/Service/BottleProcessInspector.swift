import Darwin
import Foundation

enum BottleProcessInspectionError: LocalizedError {
    case processListUnavailable

    var errorDescription: String? {
        "Secunda could not verify the shared game-space process list, so it made no session changes. Try again."
    }
}

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

    /// Every process belonging to Secunda's game space: matched by a managed
    /// bottle path in the command line, by the process's real executable
    /// living inside the selected runtime (Wine rewrites argv of system
    /// workers like winedevice.exe to cosmetic Windows paths), or by that
    /// executable living inside any other Secunda source runtime — identified
    /// by the provenance manifest every Secunda runtime carries. Leftover
    /// workers from a packaged copy or a source-tree test runtime must stay
    /// visible here even though this launcher instance never started them.
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
        else { throw BottleProcessInspectionError.processListUnavailable }
        let runtimeRoot = runtime.wineExecutable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL.path
        let bottlesDirectory = runtime.bottleRoot
            .deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL.path
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return Self.parse(psOutput: output).filter { process in
            guard process.pid != ownPID else { return false }
            let executablePath = Self.executablePath(of: process.pid)
            return Self.matches(
                process,
                bottlesDirectory: bottlesDirectory,
                executablePath: executablePath,
                runtimeRoot: runtimeRoot,
                executableInProvenancedRuntime: executablePath
                    .map(Self.isInsideProvenancedRuntime) ?? false
            )
        }
    }

    /// The scan above, narrowed to one game's image names for the per-game
    /// sidebar action.
    func runningProcesses(
        for descriptor: GameDescriptor,
        runtime: RuntimeDescriptor
    ) async throws -> [BottleProcess] {
        try await processesInBottle(runtime: runtime).filter { process in
            Self.matchesImages(
                process.command,
                images: descriptor.processImageNames
            )
        }
    }

    /// Processes proven to belong to this exact physical bottle. Runtime
    /// provenance alone is intentionally insufficient: another bottle may
    /// use the same source runtime and must never become shutdown authority.
    func processesInBottle(runtime: RuntimeDescriptor) async throws -> [BottleProcess] {
        let bottlePath = runtime.bottleRoot.path
        return try await runningProcesses(runtime: runtime).filter { process in
            Self.belongsToBottle(
                process,
                bottlePath: bottlePath,
                environment: Self.processEnvironment(of: process.pid)
            )
        }
    }

    /// A warm launch authority must carry the exact fingerprint expected for
    /// this physical bottle. Missing or unreadable stamps require a clean,
    /// prefix-scoped handoff; foreign prefixes never become kill authority.
    func sessionRequiresRestart(
        runtime: RuntimeDescriptor,
        expectedFingerprint: String?
    ) async throws -> Bool {
        guard let expectedFingerprint else { return false }
        let bottlePath = runtime.bottleRoot.path
        let processes = try await runningProcesses(runtime: runtime)
        var hasUnresolvedAuthority = false
        let inspected = processes.compactMap {
            process -> (process: BottleProcess, environment: [String: String]?)? in
            let environment = Self.processEnvironment(of: process.pid)
            let isAuthority = Self.isWineserver(
                process,
                executablePath: Self.executablePath(of: process.pid)
            ) || Self.matchesImages(process.command, images: ["steam.exe"])
            if isAuthority, environment == nil {
                hasUnresolvedAuthority = true
            }
            guard Self.belongsToBottle(
                process,
                bottlePath: bottlePath,
                environment: environment
            ) else { return nil }
            return (process: process, environment: environment)
        }
        guard !inspected.isEmpty else { return hasUnresolvedAuthority }

        let authorities = inspected.filter { entry in
            Self.isWineserver(
                entry.process,
                executablePath: Self.executablePath(of: entry.process.pid)
            ) || Self.matchesImages(entry.process.command, images: ["steam.exe"])
        }
        let candidates = authorities.isEmpty ? inspected : authorities
        return hasUnresolvedAuthority || candidates.contains { entry in
            entry.environment?[RuntimeManager.sessionFingerprintKey] != expectedFingerprint
        }
    }

    func waitForBottleQuiescence(
        runtime: RuntimeDescriptor,
        attempts: Int = 20,
        interval: Duration = .milliseconds(250)
    ) async throws -> Bool {
        let boundedAttempts = max(1, attempts)
        for attempt in 0..<boundedAttempts {
            if try await processesInBottle(runtime: runtime).isEmpty { return true }
            if attempt + 1 < boundedAttempts {
                try await Task.sleep(for: interval)
            }
        }
        return false
    }

    /// The wineserver proven to own this exact bottle, with its Unix
    /// environment when the kernel will share it. A foreign or unreadable
    /// server is never returned as the selected session.
    func gameSpaceWineserver(
        runtime: RuntimeDescriptor
    ) async throws -> (process: BottleProcess, environment: [String: String]?)? {
        let servers = try await runningProcesses(runtime: runtime).filter { process in
            Self.isWineserver(process, executablePath: Self.executablePath(of: process.pid))
        }
        guard !servers.isEmpty else { return nil }
        let inspected = servers.map { ($0, Self.processEnvironment(of: $0.pid)) }
        let owned = inspected.first { _, environment in
            environment?["WINEPREFIX"] == runtime.bottleRoot.path
        }
        return owned
    }

    static func belongsToBottle(
        _ process: BottleProcess,
        bottlePath: String,
        environment: [String: String]?
    ) -> Bool {
        let root = URL(fileURLWithPath: bottlePath)
            .resolvingSymlinksInPath().standardizedFileURL.path
        if let prefix = environment?["WINEPREFIX"] {
            let resolvedPrefix = URL(fileURLWithPath: prefix)
                .resolvingSymlinksInPath().standardizedFileURL.path
            if resolvedPrefix == root { return true }
        }
        let rawRoot = URL(fileURLWithPath: bottlePath).standardizedFileURL.path
        return process.command.contains(rawRoot + "/")
            || process.command.contains(root + "/")
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
        bottlesDirectory: String,
        executablePath: String?,
        runtimeRoot: String,
        executableInProvenancedRuntime: Bool = false
    ) -> Bool {
        if process.command.contains(bottlesDirectory + "/") { return true }
        if let executablePath {
            let resolved = URL(fileURLWithPath: executablePath)
                .resolvingSymlinksInPath().standardizedFileURL.path
            if resolved.hasPrefix(runtimeRoot + "/") { return true }
        }
        return executableInProvenancedRuntime
    }

    /// True when this executable lives inside some Secunda source runtime,
    /// selected or not. wineserver sits one directory below the runtime root
    /// (bin/), and Windows processes report the unix loader three below
    /// (lib/wine/x86_64-unix/wine), so a short ancestor walk finds the
    /// provenance manifest without scanning the disk.
    static func isInsideProvenancedRuntime(_ executablePath: String) -> Bool {
        var directory = URL(fileURLWithPath: executablePath)
            .resolvingSymlinksInPath().standardizedFileURL
            .deletingLastPathComponent()
        for _ in 0..<6 {
            let manifest = directory
                .appendingPathComponent(SourceRuntimePolicy.provenanceRelativePath)
            if FileManager.default.fileExists(atPath: manifest.path) { return true }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { break }
            directory = parent
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

    /// wineserver identifies by its real executable; the ps command line is
    /// authoritative only when proc_pidpath has nothing.
    static func isWineserver(_ process: BottleProcess, executablePath: String?) -> Bool {
        if let executablePath {
            return URL(fileURLWithPath: executablePath).lastPathComponent == "wineserver"
        }
        return process.displayName == "wineserver"
    }

    /// The Unix environment another same-user process was started with, via
    /// KERN_PROCARGS2. Some Wine children rearrange that region and become
    /// unreadable; callers must treat nil as "cannot verify", never "clean".
    static func processEnvironment(of pid: Int32) -> [String: String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 4 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return Self.parseProcArgs2(Data(buffer.prefix(size)))
    }

    /// KERN_PROCARGS2 layout: little-endian argc, the exec path, NUL
    /// padding, argc argv strings, then environment strings. argv is
    /// consumed by count so an argument containing '=' can't masquerade as
    /// a variable; the environment ends at the first string without '='.
    static func parseProcArgs2(_ data: Data) -> [String: String]? {
        guard data.count > 4 else { return nil }
        let argc = data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0, argc < 4096 else { return nil }

        let bytes = [UInt8](data.dropFirst(4))
        var strings: [String] = []
        var start = bytes.startIndex
        var index = bytes.startIndex
        while index < bytes.endIndex {
            if bytes[index] == 0 {
                if index > start,
                   let string = String(bytes: bytes[start..<index], encoding: .utf8) {
                    strings.append(string)
                }
                start = index + 1
            }
            index += 1
        }
        // Drop the exec path, then argv by count; what follows is the
        // environment until the first non-variable string.
        guard strings.count > Int(argc) else { return nil }
        var environment: [String: String] = [:]
        for entry in strings.dropFirst(1 + Int(argc)) {
            guard let separator = entry.firstIndex(of: "=") else { break }
            let key = String(entry[entry.startIndex..<separator])
            guard !key.isEmpty else { continue }
            environment[key] = String(entry[entry.index(after: separator)...])
        }
        return environment
    }
}
