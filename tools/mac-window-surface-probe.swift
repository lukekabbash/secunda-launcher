import CoreGraphics
import Foundation

let requestedPIDs = Set(CommandLine.arguments.dropFirst().compactMap(Int32.init))
guard !requestedPIDs.isEmpty else {
    FileHandle.standardError.write(Data("usage: mac-window-surface-probe <pid> [...]\n".utf8))
    exit(64)
}

let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
    as? [[CFString: Any]] ?? []

for entry in entries {
    guard let ownerPID = (entry[kCGWindowOwnerPID] as? NSNumber)?.int32Value,
          requestedPIDs.contains(ownerPID),
          let bounds = entry[kCGWindowBounds] as? [String: NSNumber]
    else { continue }

    let windowID = (entry[kCGWindowNumber] as? NSNumber)?.uint32Value ?? 0
    let layer = (entry[kCGWindowLayer] as? NSNumber)?.intValue ?? -1
    let alpha = (entry[kCGWindowAlpha] as? NSNumber)?.doubleValue ?? 0
    let onscreen = (entry[kCGWindowIsOnscreen] as? NSNumber)?.boolValue ?? false
    let x = bounds["X"]?.intValue ?? 0
    let y = bounds["Y"]?.intValue ?? 0
    let width = bounds["Width"]?.intValue ?? 0
    let height = bounds["Height"]?.intValue ?? 0
    print("pid=\(ownerPID) window=\(windowID) onscreen=\(onscreen) layer=\(layer) alpha=\(alpha) x=\(x) y=\(y) width=\(width) height=\(height)")
}
