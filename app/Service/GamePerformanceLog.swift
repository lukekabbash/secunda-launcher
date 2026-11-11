import Darwin
import Foundation

/// One reading of a running game's own counters, taken from the kernel with
/// `proc_pidinfo`. Read-only: nothing here touches the game.
struct GameProcessCounters: Equatable, Sendable {
    var cpuNanoseconds: UInt64
    var faults: Int64
    var contextSwitches: Int64
    var machCalls: Int64
    var unixCalls: Int64
    var threads: Int32
    var residentBytes: UInt64

    static func read(pid: Int32) -> GameProcessCounters? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = info.pti_total_user + info.pti_total_system
        let nanoseconds = timebase.denom == 0
            ? ticks
            : ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
        return GameProcessCounters(
            cpuNanoseconds: nanoseconds,
            faults: Int64(info.pti_faults),
            contextSwitches: Int64(info.pti_csw),
            machCalls: Int64(info.pti_syscalls_mach),
            unixCalls: Int64(info.pti_syscalls_unix),
            threads: info.pti_threadnum,
            residentBytes: info.pti_resident_size
        )
    }
}

/// Local log of how hard a running game works the Mac, sampled
/// every few seconds while it runs. Page faults and context switches are the
/// figures that matter for Black Ops II: its copy protection runs through
/// Secunda's debug-register emulation, and every emulated breakpoint costs a
/// fault and a round trip through macOS.
final class GamePerformanceLog {
    static let fileName = "game-performance.log"
    static let maximumBytes = 2_000_000

    private let url: URL
    private var previous: [Int32: (date: Date, counters: GameProcessCounters)] = [:]

    init(logsDirectory: URL) {
        url = logsDirectory.appendingPathComponent(Self.fileName)
    }

    /// Record every running catalog game in `processes`. Processes that have
    /// ended are forgotten; a new process starts a fresh baseline.
    func record(_ processes: [BottleProcess], now: Date = Date()) {
        var seen = Set<Int32>()
        for process in processes {
            guard let game = Self.game(for: process) else { continue }
            seen.insert(process.pid)
            guard let counters = GameProcessCounters.read(pid: process.pid) else { continue }
            if let last = previous[process.pid] {
                append(Self.line(
                    gameID: game.id,
                    pid: process.pid,
                    interval: now.timeIntervalSince(last.date),
                    previous: last.counters,
                    current: counters,
                    date: now
                ))
            }
            previous[process.pid] = (now, counters)
        }
        previous = previous.filter { seen.contains($0.key) }
    }

    static func game(for process: BottleProcess) -> GameDescriptor? {
        GameDescriptor.supported.first {
            BottleProcessInspector.matchesImages(process.command, images: [$0.gameImageName])
        }
    }

    /// One tab-free, grep-friendly line per sample. Rates are per second.
    static func line(
        gameID: String,
        pid: Int32,
        interval: TimeInterval,
        previous: GameProcessCounters,
        current: GameProcessCounters,
        date: Date
    ) -> String? {
        guard interval > 0.5 else { return nil }
        func rate(_ now: Int64, _ before: Int64) -> Int {
            Int((Double(max(0, now - before)) / interval).rounded())
        }
        let cpu = Double(current.cpuNanoseconds &- previous.cpuNanoseconds) / (interval * 1e9) * 100
        let stamp = ISO8601DateFormatter().string(from: date)
        return "\(stamp) game=\(gameID) pid=\(pid)"
            + " cpu=\(Int(cpu.rounded()))%"
            + " faults/s=\(rate(current.faults, previous.faults))"
            + " switches/s=\(rate(current.contextSwitches, previous.contextSwitches))"
            + " mach/s=\(rate(current.machCalls, previous.machCalls))"
            + " unix/s=\(rate(current.unixCalls, previous.unixCalls))"
            + " threads=\(current.threads)"
            + " rss=\(current.residentBytes / 1_048_576)MiB"
    }

    private func append(_ line: String?) {
        guard let line else { return }
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int,
           size > Self.maximumBytes {
            let older = url.deletingPathExtension().appendingPathExtension("1.log")
            try? manager.removeItem(at: older)
            try? manager.moveItem(at: url, to: older)
        }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
