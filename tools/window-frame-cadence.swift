import CoreMedia
import CoreVideo
import Darwin
import Foundation
import ScreenCaptureKit

private struct Options {
    let processID: pid_t
    let windowID: CGWindowID
    let duration: Double
    let targetFPS: Double
    let reportPath: String
}

private struct NumericSummary {
    let count: Int
    let minimum: Double
    let mean: Double
    let p50: Double
    let p95: Double
    let p99: Double
    let maximum: Double
}

private struct CaptureSnapshot {
    let completeFrames: Int
    let noncompleteFrames: Int
    let frameIntervalsMS: [Double]
    let visualChangeIntervalsMS: [Double]
    let visualChanges: Int
    let sampledWidth: Int
    let sampledHeight: Int
    let stoppedError: String?
}

private func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("Window cadence probe failed: \(message)\n".utf8))
    exit(code)
}

private func usage() -> Never {
    fail("usage: swift tools/window-frame-cadence.swift --pid PID --window-id ID --duration SECONDS --target-fps FPS --report FILE, or --self-test")
}

private func parseOptions(_ arguments: ArraySlice<String>) -> Options {
    var iterator = arguments.makeIterator()
    var processID: pid_t?
    var windowID: CGWindowID?
    var duration: Double?
    var targetFPS: Double?
    var reportPath: String?

    while let argument = iterator.next() {
        guard let value = iterator.next() else { usage() }
        switch argument {
        case "--pid": processID = pid_t(value)
        case "--window-id": windowID = CGWindowID(value)
        case "--duration": duration = Double(value)
        case "--target-fps": targetFPS = Double(value)
        case "--report": reportPath = value
        default: usage()
        }
    }

    guard let processID, processID > 0,
          let windowID, windowID > 0,
          let duration, duration >= 2, duration <= 60,
          let targetFPS, targetFPS >= 1, targetFPS <= 240,
          let reportPath else {
        usage()
    }
    return Options(
        processID: processID,
        windowID: windowID,
        duration: duration,
        targetFPS: targetFPS,
        reportPath: reportPath
    )
}

private func percentile(_ sortedValues: [Double], probability: Double) -> Double {
    guard let first = sortedValues.first else { return 0 }
    guard sortedValues.count > 1 else { return first }
    let position = probability * Double(sortedValues.count - 1)
    let lower = Int(floor(position))
    let upper = Int(ceil(position))
    if lower == upper { return sortedValues[lower] }
    let fraction = position - Double(lower)
    return sortedValues[lower] + (sortedValues[upper] - sortedValues[lower]) * fraction
}

private func summarize(_ values: [Double]) -> NumericSummary? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    return NumericSummary(
        count: values.count,
        minimum: sorted[0],
        mean: values.reduce(0, +) / Double(values.count),
        p50: percentile(sorted, probability: 0.50),
        p95: percentile(sorted, probability: 0.95),
        p99: percentile(sorted, probability: 0.99),
        maximum: sorted[sorted.count - 1]
    )
}

private func fixed(_ value: Double) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
}

private func metricLines(prefix: String, summary: NumericSummary?) -> [String] {
    guard let summary else { return ["\(prefix)_COUNT=0"] }
    return [
        "\(prefix)_COUNT=\(summary.count)",
        "\(prefix)_MIN=\(fixed(summary.minimum))",
        "\(prefix)_MEAN=\(fixed(summary.mean))",
        "\(prefix)_P50=\(fixed(summary.p50))",
        "\(prefix)_P95=\(fixed(summary.p95))",
        "\(prefix)_P99=\(fixed(summary.p99))",
        "\(prefix)_MAX=\(fixed(summary.maximum))",
    ]
}

private func machSeconds(_ value: UInt64) -> Double {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return Double(value) * Double(info.numer) / Double(info.denom) / 1_000_000_000
}

private func visualHash(_ buffer: CVPixelBuffer) -> UInt64? {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    guard width > 0, height > 0, bytesPerRow >= width * 4 else { return nil }

    let columns = min(width, 24)
    let rows = min(height, 14)
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    var hash: UInt64 = 14_695_981_039_346_656_037

    for row in 0..<rows {
        let y = rows == 1 ? 0 : row * (height - 1) / (rows - 1)
        for column in 0..<columns {
            let x = columns == 1 ? 0 : column * (width - 1) / (columns - 1)
            let offset = y * bytesPerRow + x * 4
            for component in 0..<3 {
                hash ^= UInt64(bytes[offset + component] >> 3)
                hash &*= 1_099_511_628_211
            }
        }
    }
    return hash
}

private final class FrameCollector: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var completeFrames = 0
    private var noncompleteFrames = 0
    private var timestamps: [Double] = []
    private var visualChangeTimestamps: [Double] = []
    private var lastVisualHash: UInt64?
    private var sampledWidth = 0
    private var sampledHeight = 0
    private var stoppedError: String?

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid,
              let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer,
                  createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let rawStatus = (attachments[.status] as? NSNumber)?.intValue,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            return
        }

        guard status == .complete else {
            lock.withLock { noncompleteFrames += 1 }
            return
        }

        let presentationTime = sampleBuffer.presentationTimeStamp.seconds
        let timestamp: Double
        if let displayTime = attachments[.displayTime] as? UInt64, displayTime > 0 {
            timestamp = machSeconds(displayTime)
        } else if let displayTime = attachments[.displayTime] as? NSNumber,
                  displayTime.uint64Value > 0 {
            timestamp = machSeconds(displayTime.uint64Value)
        } else {
            timestamp = presentationTime
        }

        guard timestamp.isFinite, timestamp >= 0 else { return }
        let imageBuffer = sampleBuffer.imageBuffer
        let hash = imageBuffer.flatMap(visualHash)

        lock.withLock {
            completeFrames += 1
            timestamps.append(timestamp)
            if let imageBuffer {
                sampledWidth = CVPixelBufferGetWidth(imageBuffer)
                sampledHeight = CVPixelBufferGetHeight(imageBuffer)
            }
            if let hash, hash != lastVisualHash {
                visualChangeTimestamps.append(timestamp)
                lastVisualHash = hash
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { stoppedError = String(describing: type(of: error)) }
    }

    func snapshot() -> CaptureSnapshot {
        lock.withLock {
            CaptureSnapshot(
                completeFrames: completeFrames,
                noncompleteFrames: noncompleteFrames,
                frameIntervalsMS: intervals(timestamps),
                visualChangeIntervalsMS: intervals(visualChangeTimestamps),
                visualChanges: visualChangeTimestamps.count,
                sampledWidth: sampledWidth,
                sampledHeight: sampledHeight,
                stoppedError: stoppedError
            )
        }
    }

    private func intervals(_ values: [Double]) -> [Double] {
        guard values.count >= 2 else { return [] }
        return zip(values.dropFirst(), values).compactMap { newer, older in
            let interval = (newer - older) * 1000
            return interval.isFinite && interval > 0 && interval <= 2_000 ? interval : nil
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}

private func makeConfiguration(for window: SCWindow, targetFPS: Double) -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    let sourceWidth = max(1, Int(window.frame.width.rounded()))
    let sourceHeight = max(1, Int(window.frame.height.rounded()))
    let scale = min(1, 480 / Double(sourceWidth), 270 / Double(sourceHeight))
    configuration.width = max(1, Int(Double(sourceWidth) * scale))
    configuration.height = max(1, Int(Double(sourceHeight) * scale))
    configuration.minimumFrameInterval = CMTime(
        value: 1,
        timescale: CMTimeScale(targetFPS.rounded())
    )
    configuration.queueDepth = 3
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = false
    configuration.capturesAudio = false
    return configuration
}

private func buildReport(options: Options, snapshot: CaptureSnapshot) -> String {
    let budget = 1000 / options.targetFPS
    let changeRatio = snapshot.completeFrames == 0
        ? 0
        : Double(snapshot.visualChanges) / Double(snapshot.completeFrames)
    var lines = [
        "SECUNDA_WINDOW_CADENCE_FORMAT=1",
        "METHOD=screencapturekit-window-sampling",
        "CONFIDENCE=approximate-compositor-delivery",
        "LIMITATION=not-gpu-present-telemetry",
        "MOTION_REQUIRED=1",
        "PROCESS_ID=\(options.processID)",
        "WINDOW_ID=\(options.windowID)",
        "DURATION_SECONDS=\(fixed(options.duration))",
        "TARGET_FPS=\(fixed(options.targetFPS))",
        "TARGET_FRAME_BUDGET_MS=\(fixed(budget))",
        "SAMPLED_WIDTH=\(snapshot.sampledWidth)",
        "SAMPLED_HEIGHT=\(snapshot.sampledHeight)",
        "COMPLETE_FRAMES=\(snapshot.completeFrames)",
        "NONCOMPLETE_FRAMES=\(snapshot.noncompleteFrames)",
        "VISUAL_CHANGE_FRAMES=\(snapshot.visualChanges)",
        "VISUAL_CHANGE_RATIO=\(fixed(changeRatio))",
        "MOTION_SIGNAL=\(changeRatio >= 0.20 ? "PRESENT" : "LOW")",
        "CAPTURE_RESULT=\(snapshot.frameIntervalsMS.isEmpty ? "NO_DATA" : "PASS")",
        "STREAM_STOP_ERROR=\(snapshot.stoppedError ?? "none")",
    ]
    lines += metricLines(prefix: "COMPOSITOR_INTERVAL_MS", summary: summarize(snapshot.frameIntervalsMS))
    lines += metricLines(
        prefix: "VISUAL_CHANGE_INTERVAL_MS",
        summary: summarize(snapshot.visualChangeIntervalsMS)
    )
    lines += [
        "COMPOSITOR_OVER_1_5X_BUDGET=\(snapshot.frameIntervalsMS.filter { $0 > budget * 1.5 }.count)",
        "COMPOSITOR_OVER_2X_BUDGET=\(snapshot.frameIntervalsMS.filter { $0 > budget * 2 }.count)",
        "COMPOSITOR_OVER_3X_BUDGET=\(snapshot.frameIntervalsMS.filter { $0 > budget * 3 }.count)",
        "PRIVACY=pixels-titles-arguments-and-environments-not-recorded",
    ]
    return lines.joined(separator: "\n") + "\n"
}

private func runSelfTest() -> Never {
    let values = [10.0, 20.0, 30.0]
    let summary = summarize(values)
    let checks = [
        percentile(values, probability: 0.50) == 20,
        summary?.mean == 20,
        summary?.p95 == 29,
        fixed(1000 / 60.0) == "16.667",
    ]
    guard checks.allSatisfy({ $0 }) else {
        fail("self-test assertion failed", code: 1)
    }
    print("PASS: compositor cadence statistics and thresholds are deterministic.")
    exit(0)
}

private func main() {
    let arguments = CommandLine.arguments.dropFirst()
    if Array(arguments) == ["--self-test"] {
        runSelfTest()
    }
    let options = parseOptions(arguments)

    let contentSemaphore = DispatchSemaphore(value: 0)
    var shareableContent: SCShareableContent?
    var contentError: Error?
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
        shareableContent = content
        contentError = error
        contentSemaphore.signal()
    }
    contentSemaphore.wait()
    if contentError != nil { fail("ScreenCaptureKit content discovery failed", code: 69) }

    guard let window = shareableContent?.windows.first(where: {
        $0.windowID == options.windowID
            && $0.owningApplication?.processID == options.processID
            && $0.isOnScreen
    }) else {
        fail("exact onscreen window does not belong to the requested PID", code: 66)
    }

    let collector = FrameCollector()
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = makeConfiguration(for: window, targetFPS: options.targetFPS)
    let stream = SCStream(filter: filter, configuration: configuration, delegate: collector)
    let queue = DispatchQueue(label: "com.secunda.window-cadence", qos: .userInitiated)

    do {
        try stream.addStreamOutput(collector, type: .screen, sampleHandlerQueue: queue)
    } catch {
        fail("could not attach the exact-window sampler", code: 69)
    }

    let startSemaphore = DispatchSemaphore(value: 0)
    var startError: Error?
    stream.startCapture { error in
        startError = error
        startSemaphore.signal()
    }
    startSemaphore.wait()
    if startError != nil { fail("screen capture could not start", code: 69) }

    RunLoop.current.run(until: Date().addingTimeInterval(options.duration))

    let stopSemaphore = DispatchSemaphore(value: 0)
    stream.stopCapture { _ in stopSemaphore.signal() }
    _ = stopSemaphore.wait(timeout: .now() + 5)

    let report = buildReport(options: options, snapshot: collector.snapshot())
    do {
        try Data(report.utf8).write(
            to: URL(fileURLWithPath: options.reportPath),
            options: .atomic
        )
    } catch {
        fail("unable to write report", code: 73)
    }
}

main()
