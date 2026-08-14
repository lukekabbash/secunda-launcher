import AppKit
import CoreGraphics

struct HostDisplayModes: Equatable, Sendable {
    let active: DisplayExtent?
    let activePixels: DisplayExtent?
    let switchable: [DisplayExtent]

    static let unavailable = HostDisplayModes(
        active: nil,
        activePixels: nil,
        switchable: []
    )

    var supportsTwoXRetina: Bool {
        guard let active, let activePixels else { return false }
        return activePixels == active.scaled(by: 2)
    }

    /// Wine doubles only the original display mode while its Retina mapping
    /// is active. Alternate physical modes remain in CoreGraphics points.
    func wineCoordinates(retinaMode: Bool) -> HostDisplayModes {
        guard retinaMode, let active else { return self }
        let wineActive = active.scaled(by: 2)
        var seen = Set<String>()
        let converted = switchable.compactMap { mode -> DisplayExtent? in
            let value = mode == active ? wineActive : mode
            return seen.insert("\(value.width)x\(value.height)").inserted ? value : nil
        }
        return HostDisplayModes(
            active: wineActive,
            activePixels: activePixels,
            switchable: converted
        )
    }
}

/// Reads the same point-space CoreGraphics modes Wine's Mac driver exposes
/// when Retina virtualization is disabled for a native-DPI game session.
enum HostDisplayModeCatalog {
    /// Wine's display switching targets the CoreGraphics main display. The
    /// key-window screen can differ on a multi-monitor desktop.
    static func wineMainScreen() -> NSScreen? {
        let displayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return false }
            return CGDirectDisplayID(number.uint32Value) == displayID
        } ?? NSScreen.main
    }

    static func modes(for screen: NSScreen?) -> HostDisplayModes {
        guard let screen,
              let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
              ] as? NSNumber
        else { return .unavailable }

        let displayID = CGDirectDisplayID(number.uint32Value)
        let activeMode = CGDisplayCopyDisplayMode(displayID)
        let active = activeMode.map {
            DisplayExtent(width: Int($0.width), height: Int($0.height))
        }
        let activePixels = activeMode.map {
            DisplayExtent(width: Int($0.pixelWidth), height: Int($0.pixelHeight))
        }
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let hostModes = CGDisplayCopyAllDisplayModes(displayID, options)
            as? [CGDisplayMode] ?? []

        var switchable: [DisplayExtent] = []
        var seen = Set<String>()
        func add(_ extent: DisplayExtent) {
            guard extent.isUsable,
                  seen.insert("\(extent.width)x\(extent.height)").inserted
            else { return }
            switchable.append(extent)
        }

        // Wine always retains the original mode. Its Apple-silicon path then
        // accepts every mode carrying CoreGraphics' valid flag; safe-flag
        // filtering is intentionally bypassed on this architecture.
        if let active { add(active) }
        for mode in hostModes where mode.ioFlags & UInt32(kDisplayModeValidFlag) != 0 {
            add(DisplayExtent(width: Int(mode.width), height: Int(mode.height)))
        }

        return HostDisplayModes(
            active: active,
            activePixels: activePixels,
            switchable: switchable
        )
    }
}
