import Foundation

private struct Options {
    let inputPath: String
    let processID: Int32
    let windowID: UInt32
    let targetFPS: Double
    let reportPath: String
}

private struct FrameBatch {
    let firstFrameNumber: UInt64
    let graphicsMemory: Double
    let processMemory: Double
    let presentIntervals: [Double]
    let gpuTimes: [Double]
}

private struct ShaderSummary {
    var eventCount = 0
    var cacheHits = 0
    var cacheMisses = 0
    var unknownCacheResults = 0
    var reportedCompilationTimes: [Double] = []
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

private func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("Metal HUD probe failed: \(message)\n".utf8))
    exit(code)
}

private func usage() -> Never {
    fail("usage: swift tools/metal-hud-probe.swift --input FILE --pid PID --window-id ID --target-fps FPS --report FILE, or --self-test")
}

private func parseOptions(_ arguments: ArraySlice<String>) -> Options {
    var iterator = arguments.makeIterator()
    var inputPath: String?
    var processID: Int32?
    var windowID: UInt32?
    var targetFPS: Double?
    var reportPath: String?

    while let argument = iterator.next() {
        guard let value = iterator.next() else { usage() }
        switch argument {
        case "--input":
            inputPath = value
        case "--pid":
            processID = Int32(value)
        case "--window-id":
            windowID = UInt32(value)
        case "--target-fps":
            targetFPS = Double(value)
        case "--report":
            reportPath = value
        default:
            usage()
        }
    }

    guard let inputPath,
          let processID, processID > 0,
          let windowID, windowID > 0,
          let targetFPS, targetFPS >= 1, targetFPS <= 240,
          let reportPath else {
        usage()
    }

    return Options(
        inputPath: inputPath,
        processID: processID,
        windowID: windowID,
        targetFPS: targetFPS,
        reportPath: reportPath
    )
}

private func integer(_ value: Any?) -> Int32? {
    if let number = value as? NSNumber { return number.int32Value }
    if let text = value as? String { return Int32(text) }
    return nil
}

private func eventMessages(in data: Data, processID: Int32) -> [String] {
    guard let text = String(data: data, encoding: .utf8) else { return [] }

    return text.split(whereSeparator: \Character.isNewline).compactMap { line in
        guard let lineData = String(line).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: lineData),
              let dictionary = object as? [String: Any],
              let message = dictionary["eventMessage"] as? String else {
            return nil
        }

        if let recordedPID = integer(dictionary["processID"]), recordedPID != processID {
            return nil
        }
        return message
    }
}

private func parseFrameBatch(_ message: String) -> FrameBatch? {
    guard let marker = message.range(of: "metal-HUD:") else { return nil }
    let payload = message[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    let fields = payload.split(separator: ",", omittingEmptySubsequences: false)
    guard fields.count >= 5,
          (fields.count - 3).isMultiple(of: 2),
          let firstFrameNumber = UInt64(fields[0].trimmingCharacters(in: .whitespaces)),
          let graphicsMemory = Double(fields[1].trimmingCharacters(in: .whitespaces)),
          let processMemory = Double(fields[2].trimmingCharacters(in: .whitespaces)),
          graphicsMemory.isFinite,
          processMemory.isFinite else {
        return nil
    }

    var intervals: [Double] = []
    var gpuTimes: [Double] = []
    var index = 3
    while index < fields.count {
        guard let interval = Double(fields[index].trimmingCharacters(in: .whitespaces)),
              let gpuTime = Double(fields[index + 1].trimmingCharacters(in: .whitespaces)),
              interval.isFinite, interval >= 0,
              gpuTime.isFinite, gpuTime >= 0 else {
            return nil
        }
        intervals.append(interval)
        gpuTimes.append(gpuTime)
        index += 2
    }

    return FrameBatch(
        firstFrameNumber: firstFrameNumber,
        graphicsMemory: graphicsMemory,
        processMemory: processMemory,
        presentIntervals: intervals,
        gpuTimes: gpuTimes
    )
}

private func firstMatch(in text: String, pattern: String) -> String? {
    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.firstMatch(
              in: text,
              range: NSRange(text.startIndex..., in: text)
          ),
          match.numberOfRanges >= 2,
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return String(text[range])
}

private func summarizeShaders(_ messages: [String]) -> ShaderSummary {
    var summary = ShaderSummary()
    for message in messages where message.contains("CompileShader:") {
        summary.eventCount += 1

        switch firstMatch(in: message, pattern: #"cached:\s*([0-9]+)"#) {
        case "0": summary.cacheMisses += 1
        case "1": summary.cacheHits += 1
        default: summary.unknownCacheResults += 1
        }

        if let rawTime = firstMatch(in: message, pattern: #"compilation-time:\s*([0-9]+(?:\.[0-9]+)?)"#),
           let time = Double(rawTime), time.isFinite {
            summary.reportedCompilationTimes.append(time)
        }
    }
    return summary
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

private func buildReport(
    options: Options,
    messages: [String],
    batches: [FrameBatch],
    shaders: ShaderSummary
) -> String {
    let intervals = batches.flatMap(\.presentIntervals)
    let gpuTimes = batches.flatMap(\.gpuTimes)
    let frameBudget = 1000 / options.targetFPS
    let firstFrame = batches.map(\.firstFrameNumber).min()
    let lastFrame = batches.map { batch in
        batch.firstFrameNumber + UInt64(max(0, batch.presentIntervals.count - 1))
    }.max()
    let graphicsMemory = batches.map(\.graphicsMemory)
    let processMemory = batches.map(\.processMemory)

    var lines = [
        "SECUNDA_METAL_HUD_FORMAT=1",
        "METHOD=apple-metal-performance-hud",
        "PROCESS_ID=\(options.processID)",
        "WINDOW_ID=\(options.windowID)",
        "TARGET_FPS=\(fixed(options.targetFPS))",
        "TARGET_FRAME_BUDGET_MS=\(fixed(frameBudget))",
        "PERCENTILE_METHOD=linear-interpolation",
        "HUD_EVENT_MESSAGES=\(messages.count)",
        "HUD_FRAME_BATCHES=\(batches.count)",
        "HUD_FIRST_FRAME_NUMBER=\(firstFrame.map(String.init) ?? "unavailable")",
        "HUD_LAST_FRAME_NUMBER=\(lastFrame.map(String.init) ?? "unavailable")",
        "FRAME_DATA_RESULT=\(intervals.isEmpty ? "NO_DATA" : "PASS")",
    ]
    lines += metricLines(prefix: "PRESENT_INTERVAL_MS", summary: summarize(intervals))
    lines += metricLines(prefix: "GPU_TIME_MS", summary: summarize(gpuTimes))
    lines += metricLines(prefix: "GRAPHICS_MEMORY_REPORTED", summary: summarize(graphicsMemory))
    lines += metricLines(prefix: "PROCESS_MEMORY_REPORTED", summary: summarize(processMemory))
    lines += [
        "PRESENT_OVER_1_5X_BUDGET=\(intervals.filter { $0 > frameBudget * 1.5 }.count)",
        "PRESENT_OVER_2X_BUDGET=\(intervals.filter { $0 > frameBudget * 2 }.count)",
        "PRESENT_OVER_3X_BUDGET=\(intervals.filter { $0 > frameBudget * 3 }.count)",
        "SHADER_EVENT_COUNT=\(shaders.eventCount)",
        "SHADER_CACHE_HITS=\(shaders.cacheHits)",
        "SHADER_CACHE_MISSES=\(shaders.cacheMisses)",
        "SHADER_CACHE_UNKNOWN=\(shaders.unknownCacheResults)",
        "SHADER_REPORTED_TIME_UNIT=apple-hud-raw",
    ]
    lines += metricLines(
        prefix: "SHADER_REPORTED_COMPILATION_TIME",
        summary: summarize(shaders.reportedCompilationTimes)
    )
    lines.append("PRIVACY=raw-log-events-and-shader-names-omitted")
    return lines.joined(separator: "\n") + "\n"
}

private func runSelfTest() -> Never {
    let fixture = """
    {"processID":42,"subsystem":"com.apple.metal.hud","eventMessage":"metal-HUD: 100,12.5,44.0,16.0,5.0,17.0,6.0"}
    {"processID":42,"subsystem":"com.apple.metal.hud","eventMessage":"CompileShader: name: private-name compilation-time: 5000 cached: 0"}
    {"processID":42,"subsystem":"com.apple.metal.hud","eventMessage":"CompileShader: name: second-private-name compilation-time: 1000 cached: 1"}
    {"processID":999,"subsystem":"com.apple.metal.hud","eventMessage":"metal-HUD: 1,1,1,999,999"}
    """
    let messages = eventMessages(in: Data(fixture.utf8), processID: 42)
    let batches = messages.compactMap(parseFrameBatch)
    let shaders = summarizeShaders(messages)
    let options = Options(
        inputPath: "unused",
        processID: 42,
        windowID: 7,
        targetFPS: 60,
        reportPath: "unused"
    )
    let report = buildReport(options: options, messages: messages, batches: batches, shaders: shaders)
    let checks = [
        batches.count == 1,
        batches[0].presentIntervals == [16, 17],
        shaders.cacheHits == 1,
        shaders.cacheMisses == 1,
        report.contains("PRESENT_INTERVAL_MS_P50=16.500"),
        report.contains("FRAME_DATA_RESULT=PASS"),
        !report.contains("private-name"),
        !report.contains("999.000"),
    ]
    guard checks.allSatisfy({ $0 }) else {
        fail("self-test assertion failed", code: 1)
    }
    print("PASS: Metal HUD metrics are summarized without raw events or shader names.")
    exit(0)
}

private func main() {
    let arguments = CommandLine.arguments.dropFirst()
    if Array(arguments) == ["--self-test"] {
        runSelfTest()
    }

    let options = parseOptions(arguments)
    let inputURL = URL(fileURLWithPath: options.inputPath)
    guard let data = try? Data(contentsOf: inputURL) else {
        fail("unable to read input log", code: 66)
    }
    let messages = eventMessages(in: data, processID: options.processID)
    let batches = messages.compactMap(parseFrameBatch)
    let shaders = summarizeShaders(messages)
    let report = buildReport(options: options, messages: messages, batches: batches, shaders: shaders)

    do {
        try Data(report.utf8).write(to: URL(fileURLWithPath: options.reportPath), options: .atomic)
    } catch {
        fail("unable to write report", code: 73)
    }
}

main()
