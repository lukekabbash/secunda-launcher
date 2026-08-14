import Foundation

struct DisplayResolutionOption: Identifiable, Equatable, Sendable {
    let width: Int
    let height: Int
    let note: String?

    var id: String { "\(width)x\(height)" }

    var label: String {
        let size = "\(width) × \(height)"
        return note.map { "\(size)  (\($0))" } ?? size
    }
}

/// Produces window sizes from the active panel instead of assuming 16:9.
/// Even dimensions remain friendly to older renderers and video paths. The
/// point dimensions remain first because that is the coordinate space Wine's
/// Mac driver exposes; optional pixel dimensions keep a Retina panel's true
/// native mode available as a separate choice.
enum DisplayResolutionCatalog {
    static func capturedExclusiveOptions(
        modes: [DisplayExtent],
        active: DisplayExtent?
    ) -> [DisplayResolutionOption] {
        let activeID = active.map { "\($0.width)x\($0.height)" }
        var seen = Set<String>()
        let unique = modes.filter {
            $0.isUsable && seen.insert("\($0.width)x\($0.height)").inserted
        }
        let sorted = unique.sorted { lhs, rhs in
            let lhsID = "\(lhs.width)x\(lhs.height)"
            let rhsID = "\(rhs.width)x\(rhs.height)"
            if lhsID == activeID { return true }
            if rhsID == activeID { return false }
            let lhsArea = lhs.width * lhs.height
            let rhsArea = rhs.width * rhs.height
            if lhsArea != rhsArea { return lhsArea > rhsArea }
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            return lhs.height > rhs.height
        }
        return sorted.map { mode in
            let id = "\(mode.width)x\(mode.height)"
            return DisplayResolutionOption(
                width: mode.width,
                height: mode.height,
                note: id == activeID ? "Current Display Mode" : "Switchable Display Mode"
            )
        }
    }

    static func options(
        screenWidth: Int,
        screenHeight: Int,
        currentWidth: Int,
        currentHeight: Int,
        screenPixelWidth: Int? = nil,
        screenPixelHeight: Int? = nil
    ) -> [DisplayResolutionOption] {
        var options: [DisplayResolutionOption] = []
        var seen = Set<String>()

        func add(_ width: Int, _ height: Int, note: String? = nil) {
            guard width > 0, height > 0 else { return }
            let option = DisplayResolutionOption(width: width, height: height, note: note)
            guard seen.insert(option.id).inserted else { return }
            options.append(option)
        }

        if screenWidth > 0, screenHeight > 0 {
            add(screenWidth, screenHeight, note: "This Display")
            if let screenPixelWidth, let screenPixelHeight,
               screenPixelWidth != screenWidth || screenPixelHeight != screenHeight {
                add(screenPixelWidth, screenPixelHeight, note: "Native Pixels")
            }
            for (scale, label) in [(0.84, "Large"), (0.75, "Medium"), (0.60, "Compact")] {
                add(even(screenWidth, scaledBy: scale), even(screenHeight, scaledBy: scale), note: label)
            }
        }

        add(currentWidth, currentHeight, note: "Current")
        for (width, height, label, alwaysAvailable) in [
            // Keep the common UHD mode available even when macOS exposes a
            // Retina panel as a smaller logical desktop.
            (3840, 2160, "4K UHD", true),
            (1680, 1050, "16:10", false), (1440, 900, "16:10", false),
            (1280, 800, "16:10", false), (1600, 900, "16:9", false),
            (1366, 768, "16:9", false), (1280, 720, "16:9", false)
        ] where alwaysAvailable
                || screenWidth <= 0
                || (width <= screenWidth && height <= screenHeight) {
            add(width, height, note: label)
        }
        return options
    }

    private static func even(_ value: Int, scaledBy scale: Double) -> Int {
        max(2, Int((Double(value) * scale / 2).rounded()) * 2)
    }
}
