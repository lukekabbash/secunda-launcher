import Foundation

/// Integer dimensions shared with Wine and game command lines. AppKit owns
/// the conversion from screen rectangles; launch code consumes this contract.
struct DisplayExtent: Equatable, Sendable {
    let width: Int
    let height: Int

    var isUsable: Bool { width > 0 && height > 0 }

    func scaled(by factor: Double) -> DisplayExtent {
        guard factor > 0 else { return self }
        return DisplayExtent(
            width: Int((Double(width) * factor).rounded()),
            height: Int((Double(height) * factor).rounded())
        )
    }

    /// Preserve aspect ratio while fitting a decorated window. Independent
    /// axis clamps stretch the UI and desynchronize its mouse hit map.
    func fitting(_ requested: DisplayExtent) -> DisplayExtent {
        guard isUsable, requested.isUsable,
              requested.width > width || requested.height > height
        else { return requested }

        let scale = min(
            Double(width) / Double(requested.width),
            Double(height) / Double(requested.height)
        )
        return DisplayExtent(
            width: min(width, Int((Double(requested.width) * scale).rounded())),
            height: min(height, Int((Double(requested.height) * scale).rounded()))
        )
    }
}

/// Borderless play respects the panel's safe area. A decorated window must
/// also fit inside the visible work area after its title-bar chrome.
struct HostDisplayGeometry: Equatable, Sendable {
    let fullFramePoints: DisplayExtent
    let fullscreenContentPoints: DisplayExtent
    let visibleFramePoints: DisplayExtent
    let windowedContentPoints: DisplayExtent
    let backingScale: Double
    let activeFullscreenModePoints: DisplayExtent?
    let supportsTwoXRetina: Bool
    let switchableFullscreenModes: [DisplayExtent]

    init(
        fullFramePoints: DisplayExtent,
        fullscreenContentPoints: DisplayExtent,
        visibleFramePoints: DisplayExtent,
        windowedContentPoints: DisplayExtent,
        backingScale: Double,
        activeFullscreenModePoints: DisplayExtent? = nil,
        supportsTwoXRetina: Bool? = nil,
        switchableFullscreenModes: [DisplayExtent] = []
    ) {
        self.fullFramePoints = fullFramePoints
        self.fullscreenContentPoints = fullscreenContentPoints
        self.visibleFramePoints = visibleFramePoints
        self.windowedContentPoints = windowedContentPoints
        self.backingScale = backingScale
        self.activeFullscreenModePoints = activeFullscreenModePoints
            ?? (fullFramePoints.isUsable ? fullFramePoints : nil)
        self.supportsTwoXRetina = supportsTwoXRetina
            ?? (abs(backingScale - 2) < 0.01)
        self.switchableFullscreenModes = switchableFullscreenModes
    }

    static let unknown = HostDisplayGeometry(
        fullFramePoints: DisplayExtent(width: 0, height: 0),
        fullscreenContentPoints: DisplayExtent(width: 0, height: 0),
        visibleFramePoints: DisplayExtent(width: 0, height: 0),
        windowedContentPoints: DisplayExtent(width: 0, height: 0),
        backingScale: 1,
        activeFullscreenModePoints: nil,
        supportsTwoXRetina: false,
        switchableFullscreenModes: []
    )

    var fullFramePixels: DisplayExtent {
        fullFramePoints.scaled(by: backingScale)
    }

    func wineActiveFullscreenMode(retinaMode: Bool) -> DisplayExtent? {
        guard let activeFullscreenModePoints else { return nil }
        return retinaMode ? activeFullscreenModePoints.scaled(by: 2) : activeFullscreenModePoints
    }

    func wineFullscreenModes(retinaMode: Bool) -> [DisplayExtent] {
        let active = activeFullscreenModePoints
        let wineActive = wineActiveFullscreenMode(retinaMode: retinaMode)
        var seen = Set<String>()
        return switchableFullscreenModes.compactMap { mode in
            let converted = retinaMode && mode == active ? (wineActive ?? mode) : mode
            return seen.insert("\(converted.width)x\(converted.height)").inserted
                ? converted
                : nil
        }
    }

    /// Convert a valid Wine fullscreen extent back to the host frame that
    /// should cover the selected physical mode.
    func hostFrame(forWineMode mode: DisplayExtent, retinaMode: Bool) -> DisplayExtent {
        if retinaMode, mode == wineActiveFullscreenMode(retinaMode: true),
           let activeFullscreenModePoints {
            return activeFullscreenModePoints
        }
        return mode
    }

    /// Largest normal-window client sharing the safe fullscreen aspect. The
    /// drawable can scale uniformly when entering fullscreen and returns to
    /// a fully visible window without changing its coordinate map.
    var transitionSafeBorderlessContent: DisplayExtent? {
        guard fullscreenContentPoints.isUsable,
              windowedContentPoints.isUsable
        else { return nil }
        return windowedContentPoints.fitting(fullscreenContentPoints)
    }

    /// Command-line window sizes are Win32 client coordinates, which the Mac
    /// driver exposes in screen points even when the drawable is Retina-
    /// backed. Each mode gets the host content rectangle it can really own.
    func maximumContent(for mode: DisplayMode) -> DisplayExtent? {
        let points: DisplayExtent
        switch mode {
        case .borderlessFullscreen:
            points = fullscreenContentPoints
        case .exclusiveFullscreen:
            points = fullFramePoints
        case .windowed:
            points = windowedContentPoints
        }
        guard points.isUsable else { return nil }
        return points
    }
}
