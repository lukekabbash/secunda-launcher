import CoreGraphics
import Darwin
import Foundation

private struct ProcessIdentity {
    let pid: pid_t
    let parentPID: pid_t
    let name: String
    let executable: String
}

private enum TitleClass: String {
    case skyrim
    case steam
    case generic
    case absent
}

private func usage() -> Never {
    let message = "Usage: swift tools/secunda-window-probe.swift --pid PID [--pid PID]...\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(64)
}

private func parseProcessIDs(_ arguments: ArraySlice<String>) -> [pid_t] {
    var iterator = arguments.makeIterator()
    var result: [pid_t] = []

    while let argument = iterator.next() {
        guard argument == "--pid", let value = iterator.next(),
              let pid = pid_t(value), pid > 0 else {
            usage()
        }
        result.append(pid)
    }

    guard !result.isEmpty else { usage() }
    return result
}

private func processPath(for pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(cString: buffer)
}

private func processIdentity(for pid: pid_t) -> ProcessIdentity? {
    var info = proc_bsdinfo()
    let byteCount = MemoryLayout<proc_bsdinfo>.stride
    let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(byteCount))
    guard result == byteCount, let executable = processPath(for: pid) else {
        return nil
    }

    let name = withUnsafePointer(to: &info.pbi_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
            String(cString: $0)
        }
    }
    return ProcessIdentity(
        pid: pid,
        parentPID: pid_t(info.pbi_ppid),
        name: name,
        executable: executable
    )
}

private func classify(title: String?) -> TitleClass {
    guard let title, !title.isEmpty else { return .absent }
    let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    if folded.contains("skyrim") { return .skyrim }
    if folded.contains("steam") { return .steam }
    return .generic
}

private func sanitized(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
}

private func integer(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue
}

private func double(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
}

private func windowSnapshot() -> [[CFString: Any]] {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] ?? []
}

private func runSelfTest() -> Never {
    let checks = [
        classify(title: "The Elder Scrolls V: Skyrim Special Edition") == .skyrim,
        classify(title: "Steam - Library") == .steam,
        classify(title: "private account label") == .generic,
        classify(title: nil) == .absent,
        sanitized("line\nbreak") == "line\\nbreak",
    ]
    guard checks.allSatisfy({ $0 }) else {
        FileHandle.standardError.write(Data("Window probe self-test failed.\n".utf8))
        exit(1)
    }
    print("PASS: window titles are classified without being emitted.")
    exit(0)
}

let arguments = CommandLine.arguments.dropFirst()
if Array(arguments) == ["--self-test"] {
    runSelfTest()
}

let processIDs = parseProcessIDs(arguments)
let requested = Set(processIDs)

for pid in processIDs {
    guard let identity = processIdentity(for: pid) else {
        FileHandle.standardError.write(Data("Unable to inspect PID \(pid).\n".utf8))
        exit(66)
    }
    print("PROCESS pid=\(identity.pid) parent_pid=\(identity.parentPID) name=\(sanitized(identity.name)) executable=\(sanitized(identity.executable))")
}

let windows = windowSnapshot()
    .filter { info in
        guard let ownerPID = integer(info[kCGWindowOwnerPID]) else { return false }
        return requested.contains(pid_t(ownerPID))
    }
    .sorted { left, right in
        (integer(left[kCGWindowNumber]) ?? 0) < (integer(right[kCGWindowNumber]) ?? 0)
    }

for info in windows {
    guard let ownerPID = integer(info[kCGWindowOwnerPID]),
          let windowID = integer(info[kCGWindowNumber]) else {
        continue
    }
    let owner = (info[kCGWindowOwnerName] as? String).map(sanitized) ?? "unknown"
    let title = info[kCGWindowName] as? String
    let titleClass = classify(title: title).rawValue
    let titlePresent = title?.isEmpty == false
    let layer = integer(info[kCGWindowLayer]) ?? -1
    let alpha = double(info[kCGWindowAlpha]) ?? -1
    let onscreen = (info[kCGWindowIsOnscreen] as? NSNumber)?.boolValue ?? false
    let boundsDictionary = info[kCGWindowBounds] as? [String: NSNumber]
    let x = boundsDictionary?["X"]?.intValue ?? 0
    let y = boundsDictionary?["Y"]?.intValue ?? 0
    let width = boundsDictionary?["Width"]?.intValue ?? 0
    let height = boundsDictionary?["Height"]?.intValue ?? 0
    let alphaText = String(format: "%.3f", alpha)
    let identityFields = "WINDOW id=\(windowID) owner_pid=\(ownerPID) owner=\(owner)"
    let titleFields = "title_class=\(titleClass) title_present=\(titlePresent ? 1 : 0)"
    let surfaceFields = "onscreen=\(onscreen ? 1 : 0) layer=\(layer) alpha=\(alphaText)"
    let boundsFields = "x=\(x) y=\(y) width=\(width) height=\(height)"

    print("\(identityFields) \(titleFields) \(surfaceFields) \(boundsFields)")
}

for pid in processIDs where !windows.contains(where: { integer($0[kCGWindowOwnerPID]) == Int(pid) }) {
    print("WINDOW_NONE pid=\(pid)")
}
