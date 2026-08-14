import AppKit

/// Samples the physical display Wine can switch and converts AppKit chrome
/// into the client rectangles used by launch policy.
enum HostDisplayGeometryProbe {
    static func wineMainDisplay() -> HostDisplayGeometry {
        geometry(for: HostDisplayModeCatalog.wineMainScreen())
    }

    static func geometry(for screen: NSScreen?) -> HostDisplayGeometry {
        guard let screen else { return .unknown }
        let displayModes = HostDisplayModeCatalog.modes(for: screen)
        let style: NSWindow.StyleMask = [
            .titled, .closable, .miniaturizable, .resizable
        ]
        let safeContent = NSWindow.contentRect(
            forFrameRect: NSRect(origin: .zero, size: screen.visibleFrame.size),
            styleMask: style
        )
        let safeArea = screen.safeAreaInsets
        let fullscreenContent = NSSize(
            width: max(0, screen.frame.width - safeArea.left - safeArea.right),
            height: max(0, screen.frame.height - safeArea.top - safeArea.bottom)
        )
        func extent(_ size: NSSize) -> DisplayExtent {
            DisplayExtent(
                width: Int(size.width.rounded(.down)),
                height: Int(size.height.rounded(.down))
            )
        }
        return HostDisplayGeometry(
            fullFramePoints: extent(screen.frame.size),
            fullscreenContentPoints: extent(fullscreenContent),
            visibleFramePoints: extent(screen.visibleFrame.size),
            windowedContentPoints: extent(safeContent.size),
            backingScale: screen.backingScaleFactor,
            activeFullscreenModePoints: displayModes.active,
            supportsTwoXRetina: displayModes.supportsTwoXRetina,
            switchableFullscreenModes: displayModes.switchable
        )
    }
}
