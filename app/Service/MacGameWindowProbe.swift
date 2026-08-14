import AppKit
import CoreGraphics
import Foundation

/// Minimal, privacy-preserving metadata for one macOS window surface.
/// Titles and pixels are intentionally never read.
struct GameWindowSurface: Equatable, Sendable {
    let windowID: UInt32
    let ownerPID: Int32
    let isOnscreen: Bool
    let layer: Int
    let alpha: Double
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    init(
        windowID: UInt32 = 0,
        ownerPID: Int32,
        isOnscreen: Bool,
        layer: Int,
        alpha: Double,
        x: Int = 0,
        y: Int = 0,
        width: Int,
        height: Int
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.isOnscreen = isOnscreen
        self.layer = layer
        self.alpha = alpha
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var isPresentable: Bool {
        // Wine's Mac driver raises fullscreen and screen-covering borderless
        // game windows above the menu bar (and up to the shielding level in
        // captured modes), so an elevated layer is normal for a healthy
        // session. Only sub-desktop layers are disqualifying; tiny helper
        // windows are already excluded by the size floor.
        ownerPID > 0
            && layer >= 0
            && alpha > 0.01
            && width >= 320
            && height >= 180
    }

    var isVisible: Bool { isPresentable && isOnscreen }

    func covers(_ display: DisplayExtent, tolerance: Int = 8) -> Bool {
        guard display.isUsable else { return false }
        return abs(x) <= tolerance
            && abs(y) <= tolerance
            && abs(width - display.width) <= tolerance
            && abs(height - display.height) <= tolerance
    }
}

/// Confirms that a stable Windows process produced a real Mac window and
/// asks macOS to foreground it. Process lifetime alone is not launch success.
final class MacGameWindowProbe {
    func surfaces(ownedBy processIDs: Set<Int32>) -> [GameWindowSurface] {
        guard !processIDs.isEmpty else { return [] }
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[CFString: Any]] ?? []

        return info.compactMap { entry -> GameWindowSurface? in
            guard let owner = (entry[kCGWindowOwnerPID] as? NSNumber)?.int32Value,
                  processIDs.contains(owner),
                  let bounds = entry[kCGWindowBounds] as? [String: NSNumber]
            else { return nil }
            let windowID = (entry[kCGWindowNumber] as? NSNumber)?.uint32Value ?? 0
            return GameWindowSurface(
                windowID: windowID,
                ownerPID: owner,
                isOnscreen: (entry[kCGWindowIsOnscreen] as? NSNumber)?.boolValue ?? false,
                layer: (entry[kCGWindowLayer] as? NSNumber)?.intValue ?? -1,
                alpha: (entry[kCGWindowAlpha] as? NSNumber)?.doubleValue ?? 0,
                x: bounds["X"]?.intValue ?? 0,
                y: bounds["Y"]?.intValue ?? 0,
                width: bounds["Width"]?.intValue ?? 0,
                height: bounds["Height"]?.intValue ?? 0
            )
        }
    }

    func bringForward(ownerPID: Int32) {
        NSRunningApplication(processIdentifier: pid_t(ownerPID))?
            .activate(options: [.activateAllWindows])
    }
}
