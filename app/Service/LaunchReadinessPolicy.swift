import Foundation

/// Small, platform-independent policies shared by the launcher and regression tests.
enum RuntimeVersionPolicy {
    static let timeoutSeconds: TimeInterval = 5
    static let maximumOutputBytes = 4_096

    /// Parse only stdout from one successful invocation, never an accumulated log.
    static func parse(_ output: Data) -> String? {
        guard output.count <= maximumOutputBytes,
              let text = String(data: output, encoding: .utf8)
        else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count == 1, let version = lines.first,
              version.hasPrefix("wine-"), version.utf8.count <= 256,
              let first = version.dropFirst(5).utf8.first,
              (48...57).contains(first),
              version.utf8.allSatisfy({ (32...126).contains($0) })
        else { return nil }
        return version
    }
}

/// Reject unusable native-audio payloads before enabling DLL overrides.
/// This is structural validation, NOT proof of publisher identity or a signature check.
/// PE layout: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
/// Acquisition remains the existing Microsoft HTTPS redistributable path.
enum NativeAudioPayload {
    static let maximumBytes = 64 * 1_024 * 1_024

    static func validatedContents(at url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
        ]), values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumBytes,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumBytes + 1),
              isValidX64DLL(data)
        else { return nil }
        return data
    }

    static func isValidX64DLL(_ data: Data) -> Bool {
        guard data.count >= 64, data.count <= maximumBytes,
              data.range(of: Data("Wine placeholder DLL".utf8)) == nil
        else { return false }
        // Use byte reads: malformed offsets must never cause an unaligned load or trap.
        let bytes = [UInt8](data)
        func contains(_ offset: Int, _ length: Int) -> Bool {
            offset >= 0 && length >= 0 && offset <= bytes.count
                && length <= bytes.count - offset
        }
        func u16(_ offset: Int) -> Int {
            Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> Int {
            u16(offset) | (u16(offset + 2) << 16)
        }
        guard bytes[0] == 0x4d, bytes[1] == 0x5a else { return false }
        let pe = u32(0x3c)
        guard pe >= 64, contains(pe, 24), u32(pe) == 0x00004550,
              u16(pe + 4) == 0x8664,
              u16(pe + 22) & 0x2002 == 0x2002
        else { return false }
        let sections = u16(pe + 6)
        let optionalSize = u16(pe + 20)
        let optional = pe + 24
        guard (1...96).contains(sections), optionalSize >= 112,
              contains(optional, optionalSize), u16(optional) == 0x20b
        else { return false }
        let table = optional + optionalSize
        let imageSize = u32(optional + 56)
        let headersSize = u32(optional + 60)
        let directories = u32(optional + 108)
        guard imageSize > 0, headersSize >= table + sections * 40,
              headersSize <= bytes.count, headersSize <= imageSize,
              contains(table, sections * 40),
              directories <= (optionalSize - 112) / 8
        else { return false }
        var hasCode = false
        for index in 0..<sections {
            let section = table + index * 40
            let virtualSize = u32(section + 8)
            let virtualAddress = u32(section + 12)
            let rawSize = u32(section + 16)
            let rawOffset = u32(section + 20)
            guard virtualAddress <= imageSize,
                  max(virtualSize, rawSize) <= imageSize - virtualAddress
            else { return false }
            if rawSize > 0 {
                guard rawOffset >= headersSize, contains(rawOffset, rawSize) else { return false }
                if u32(section + 36) & 0x20000000 != 0 { hasCode = true }
            }
        }
        return hasCode
    }
}

/// Bounded metadata only. This file is no longer used as the probe's return channel.
enum RuntimeProbeLog {
    private static let lock = NSLock()
    private static let maximumBytes = 65_536

    static func record(
        at url: URL,
        origin: String,
        candidateID: String,
        outcome: String,
        version: String? = nil,
        exitStatus: Int32? = nil
    ) {
        var fields = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "origin": origin,
            "candidateID": candidateID,
            "outcome": outcome
        ]
        fields["version"] = version
        fields["exitStatus"] = exitStatus.map { String($0) }
        guard var data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        else { return }
        data.append(0x0a)
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else { return }
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            if size + UInt64(data.count) > UInt64(maximumBytes) {
                try handle.truncate(atOffset: 0)
                try handle.seek(toOffset: 0)
            }
            try handle.write(contentsOf: data)
        } catch {
            // A logging failure must not prevent discovery of a usable runtime.
        }
    }
}
