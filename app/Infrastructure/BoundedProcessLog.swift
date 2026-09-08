import Darwin
import Foundation

/// Drains child output continuously while keeping each diagnostic log within
/// a fixed byte budget. Once full, the remainder of that process's output is
/// discarded so a noisy long-running client cannot exhaust the host disk.
final class BoundedProcessLog: @unchecked Sendable {
    let pipe: Pipe

    private let reader: FileHandle
    private let writer: FileHandle
    private let descriptor: Int32
    private let maximumBytes: Int
    private let queue = DispatchQueue(label: "app.secunda.launcher.process-log")
    private var source: DispatchSourceRead!
    private var writtenBytes: Int
    private var finished = false

    init(url: URL, maximumBytes: Int) throws {
        precondition(maximumBytes > 0)
        try Self.prepare(url: url, maximumBytes: maximumBytes)

        let outputPipe = Pipe()
        let outputWriter = try FileHandle(forWritingTo: url)
        pipe = outputPipe
        reader = outputPipe.fileHandleForReading
        descriptor = outputPipe.fileHandleForReading.fileDescriptor
        self.maximumBytes = maximumBytes
        writer = outputWriter
        writtenBytes = Int(try outputWriter.seekToEnd())

        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            try? outputWriter.close()
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.drainAvailableBytes()
        }
        source.resume()
    }

    func childDidLaunch() {
        try? pipe.fileHandleForWriting.close()
    }

    func finish(process: Process? = nil) {
        queue.sync {
            guard !finished else { return }
            finished = true
            source.cancel()
            drainAvailableBytes()
            if let process {
                appendTermination(process)
            }
            try? reader.close()
            try? writer.close()
        }
    }

    private func appendTermination(_ process: Process) {
        let reason: String
        switch process.terminationReason {
        case .exit: reason = "exit"
        case .uncaughtSignal: reason = "uncaught-signal"
        @unknown default: reason = "unknown"
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\n[secunda-process-termination] timestamp=\(timestamp)"
            + " pid=\(process.processIdentifier) reason=\(reason)"
            + " status=\(process.terminationStatus)\n"
        append(Data(line.utf8))
    }

    private func drainAvailableBytes() {
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count > 0 {
                append(Data(bytes.prefix(count)))
                continue
            }
            if count == 0 { return }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return }
            return
        }
    }

    private func append(_ data: Data) {
        let remaining = max(0, maximumBytes - writtenBytes)
        guard remaining > 0 else { return }
        let chunk = data.prefix(remaining)
        do {
            try writer.write(contentsOf: chunk)
            writtenBytes += chunk.count
        } catch {
            writtenBytes = maximumBytes
        }
    }

    private static func prepare(url: URL, maximumBytes: Int) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: url.path) {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if size >= maximumBytes {
                let archive = url
                    .deletingPathExtension()
                    .appendingPathExtension("previous.\(url.pathExtension)")
                try? fileManager.removeItem(at: archive)
                if size == maximumBytes {
                    try fileManager.moveItem(at: url, to: archive)
                } else {
                    try fileManager.removeItem(at: url)
                }
            }
        }
        if !fileManager.fileExists(atPath: url.path) {
            guard fileManager.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }
}
