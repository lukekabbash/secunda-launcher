import Darwin
import Foundation

struct BoundedPipeCaptureSnapshot: Sendable {
    let data: Data
    let overflowed: Bool
    let readError: Int32?
}

final class BoundedPipeCapture: @unchecked Sendable {
    private let reader: FileHandle
    private let descriptor: Int32
    private let limit: Int
    private let queue = DispatchQueue(label: "app.secunda.launcher.process-capture")
    private var source: DispatchSourceRead!
    private var data = Data()
    private var overflowed = false
    private var readError: Int32?

    init(reader: FileHandle, limit: Int) throws {
        self.reader = reader
        self.descriptor = reader.fileDescriptor
        self.limit = limit

        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }

        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.drainAvailableBytes()
        }
    }

    func start() {
        source.resume()
    }

    func finish() -> BoundedPipeCaptureSnapshot {
        source.cancel()
        return queue.sync {
            drainAvailableBytes()
            try? reader.close()
            return BoundedPipeCaptureSnapshot(
                data: data,
                overflowed: overflowed,
                readError: readError
            )
        }
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
            readError = errno
            return
        }
    }

    private func append(_ chunk: Data) {
        let remaining = max(0, limit - data.count)
        if remaining > 0 {
            data.append(chunk.prefix(remaining))
        }
        if chunk.count > remaining {
            overflowed = true
        }
    }
}
