import AppKit

// Renders Secunda's app icon: the small moon over a night sky with a low
// aurora band, on the standard macOS icon squircle. Deterministic output.
// Usage: swift tools/make-app-icon.swift <output-directory>

let arguments = CommandLine.arguments
let outputRoot = URL(
    fileURLWithPath: arguments.count > 1 ? arguments[1] : "packaging/icon",
    isDirectory: true
)

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 11) & 0xFFFFFFFF) / Double(0xFFFFFFFF)
    }
}

func color(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

// Theme palette (app/View/Theme.swift).
let voidColor = color(0.018, 0.025, 0.045)
let midnight = color(0.035, 0.052, 0.085)
let slate = color(0.105, 0.125, 0.16)
let moonColor = color(0.82, 0.87, 0.91)
let frost = color(0.55, 0.70, 0.79)
let aurora = color(0.36, 0.62, 0.65)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let context = NSGraphicsContext.current?.cgContext else { return image }

    let scale = size / 1024
    func s(_ value: CGFloat) -> CGFloat { value * scale }

    // macOS icon grid: 824pt squircle centered in the 1024 canvas.
    let plate = NSRect(x: s(100), y: s(100), width: s(824), height: s(824))
    let squircle = NSBezierPath(roundedRect: plate, xRadius: s(185), yRadius: s(185))

    // Soft drop shadow behind the plate.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s(12)),
        blur: s(36),
        color: NSColor.black.withAlphaComponent(0.5).cgColor
    )
    voidColor.setFill()
    squircle.fill()
    context.restoreGState()

    squircle.addClip()

    // Night gradient.
    NSGradient(colors: [slate, midnight, voidColor], atLocations: [0.0, 0.45, 1.0], colorSpace: .deviceRGB)?
        .draw(in: plate, angle: -90)

    // Star field, deterministic.
    var random = SeededRandom(seed: 0x5EC0DA)
    for _ in 0..<46 {
        let x = plate.minX + CGFloat(random.next()) * plate.width
        let y = plate.minY + plate.height * (0.34 + CGFloat(random.next()) * 0.62)
        let radius = s(1.4 + CGFloat(random.next()) * 2.6)
        let alpha = 0.25 + random.next() * 0.55
        color(0.92, 0.94, 0.96, alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: radius, height: radius)).fill()
    }

    // Aurora band low in the sky: layered translucent strokes.
    context.saveGState()
    for layer in 0..<14 {
        let progress = CGFloat(layer) / 13
        let band = NSBezierPath()
        band.move(to: NSPoint(x: plate.minX - s(40), y: plate.minY + s(150) + progress * s(46)))
        band.curve(
            to: NSPoint(x: plate.maxX + s(40), y: plate.minY + s(210) + progress * s(40)),
            controlPoint1: NSPoint(x: plate.minX + plate.width * 0.32, y: plate.minY + s(280) + progress * s(52)),
            controlPoint2: NSPoint(x: plate.minX + plate.width * 0.68, y: plate.minY + s(96) + progress * s(38))
        )
        band.lineWidth = s(30)
        band.lineCapStyle = .round
        aurora.withAlphaComponent(0.045 + 0.035 * Double(1 - abs(progress - 0.5) * 2)).setStroke()
        band.stroke()
    }
    context.restoreGState()

    // Ground haze so the plate bottom stays quiet.
    NSGradient(
        colors: [voidColor.withAlphaComponent(0), voidColor.withAlphaComponent(0.85)],
        atLocations: [0.0, 1.0],
        colorSpace: .deviceRGB
    )?.draw(
        in: NSRect(x: plate.minX, y: plate.minY, width: plate.width, height: s(190)),
        angle: -90
    )

    // The moon: full disc with soft glow, then a shadow bite for the crescent.
    let moonCenter = NSPoint(x: plate.midX + s(58), y: plate.midY + s(96))
    let moonRadius = s(232)
    let moonRect = NSRect(
        x: moonCenter.x - moonRadius,
        y: moonCenter.y - moonRadius,
        width: moonRadius * 2,
        height: moonRadius * 2
    )

    context.saveGState()
    context.setShadow(
        offset: .zero,
        blur: s(90),
        color: frost.withAlphaComponent(0.55).cgColor
    )
    moonColor.setFill()
    NSBezierPath(ovalIn: moonRect).fill()
    context.restoreGState()

    // Disc shading toward the lit edge.
    context.saveGState()
    NSBezierPath(ovalIn: moonRect).addClip()
    NSGradient(
        colors: [color(0.93, 0.955, 0.975), moonColor, frost.withAlphaComponent(0.9)],
        atLocations: [0.0, 0.55, 1.0],
        colorSpace: .deviceRGB
    )?.draw(in: moonRect, angle: 205)

    // Craters, deterministic and sparse.
    var craterRandom = SeededRandom(seed: 0xA0BB)
    for _ in 0..<7 {
        let angle = craterRandom.next() * 2 * .pi
        let distance = CGFloat(craterRandom.next()) * moonRadius * 0.62
        let radius = s(14 + CGFloat(craterRandom.next()) * 30)
        let center = NSPoint(
            x: moonCenter.x + cos(angle) * distance,
            y: moonCenter.y + sin(angle) * distance
        )
        color(0.55, 0.63, 0.70, 0.28).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )).fill()
    }

    // Crescent bite: offset disc in the sky color eats the upper-left.
    let biteCenter = NSPoint(x: moonCenter.x - s(118), y: moonCenter.y + s(92))
    let biteRadius = moonRadius * 1.02
    let bite = NSBezierPath(ovalIn: NSRect(
        x: biteCenter.x - biteRadius,
        y: biteCenter.y - biteRadius,
        width: biteRadius * 2,
        height: biteRadius * 2
    ))
    context.saveGState()
    context.setShadow(
        offset: .zero,
        blur: s(40),
        color: voidColor.withAlphaComponent(0.9).cgColor
    )
    midnight.blended(withFraction: 0.55, of: voidColor)?.setFill()
    bite.fill()
    context.restoreGState()
    context.restoreGState()

    return image
}

func pngData(_ image: NSImage, pixels: Int) -> Data? {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    representation.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    return representation.representation(using: .png, properties: [:])
}

let iconset = outputRoot.appendingPathComponent("Secunda.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let master = drawIcon(size: 1024)
let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for entry in entries {
    guard let data = pngData(master, pixels: entry.pixels) else {
        fatalError("Could not render \(entry.name)")
    }
    try data.write(to: iconset.appendingPathComponent("\(entry.name).png"))
}
print("Wrote \(iconset.path)")
