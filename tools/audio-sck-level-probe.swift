import AppKit
import CoreAudio
import CoreGraphics
import CoreMedia
import Darwin
import Foundation
import ScreenCaptureKit

private enum WindowTitleClass: String {
    case skyrim
    case steam
    case generic
    case absent
}

private struct Options {
    let processID: pid_t
    let windowID: CGWindowID
    let expectedApplicationName: String
    let expectedBundleIdentifier: String?
    let expectedTitleClass: WindowTitleClass
    let durationSeconds: Double
    let thresholdDBFS: Double
    let reportPath: String
}

private final class HardWatchdog: @unchecked Sendable {
    private let timer: DispatchSourceTimer

    init(timeoutSeconds: Double) {
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + timeoutSeconds)
        timer.setEventHandler {
            let message = "ScreenCaptureKit audio probe exceeded its hard deadline.\n"
            FileHandle.standardError.write(Data(message.utf8))
            _exit(124)
        }
        timer.resume()
    }

    func cancel() {
        timer.setEventHandler {}
        timer.cancel()
    }
}

private final class AudioCollector: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let thresholdLinear: Double
    private var accumulator = AudioLevelAccumulator()
    private var streamStoppedWithError = false

    init(thresholdLinear: Double) {
        self.thresholdLinear = thresholdLinear
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio,
              sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              let format = PCMFormatIdentity(streamDescription: description) else {
            lock.withLock { accumulator.recordMalformedBuffer() }
            return
        }

        do {
            try sampleBuffer.withAudioBufferList { buffers, _ in
                let delta = PCMLevelDecoder.summarize(
                    buffers,
                    format: format,
                    thresholdLinear: thresholdLinear
                )
                lock.withLock {
                    accumulator.record(
                        delta,
                        frameCount: sampleBuffer.numSamples,
                        format: format
                    )
                }
            }
        } catch {
            lock.withLock { accumulator.recordMalformedBuffer() }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { streamStoppedWithError = true }
    }

    func snapshot() -> (levels: AudioLevelSnapshot, streamError: Bool) {
        lock.withLock { (accumulator.snapshot(), streamStoppedWithError) }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}

private func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("ScreenCaptureKit audio probe failed: \(message)\n".utf8))
    exit(code)
}

private func usage() -> Never {
    let text = """
    Usage:
      audio-sck-level-probe --pid PID --window-id ID \\
        --expected-app-name NAME --title-class skyrim|steam|generic|absent \\
        [--expected-bundle-id ID] [--duration SECONDS] \\
        [--threshold-dbfs DB] --report FILE

      audio-sck-level-probe --self-test

    The probe registers only ScreenCaptureKit's audio output for one exact
    window and owning PID. It receives no screen/pixel output and writes no
    PCM data. Its report contains aggregate levels and sanitized identity-match
    results only. Audio filtering is application-level, so audio from another
    window of the same native app may be mixed. A Wine game may emit audio from
    a native process other than the process that owns its selected window.

    macOS requires the probe's fixed code-signing identity to have Screen
    Recording permission (called Screen & System Audio Recording on current
    macOS). The first approval can require restarting the probe. This command
    never changes output volume or mute state.
    """
    print(text)
    exit(64)
}

private func parseOptions(_ arguments: ArraySlice<String>) -> Options {
    var iterator = arguments.makeIterator()
    var processID: pid_t?
    var windowID: CGWindowID?
    var expectedApplicationName: String?
    var expectedBundleIdentifier: String?
    var expectedTitleClass: WindowTitleClass?
    var durationSeconds = 10.0
    var thresholdDBFS = -60.0
    var reportPath: String?

    while let argument = iterator.next() {
        guard let value = iterator.next() else { usage() }
        switch argument {
        case "--pid": processID = pid_t(value)
        case "--window-id": windowID = CGWindowID(value)
        case "--expected-app-name": expectedApplicationName = value
        case "--expected-bundle-id": expectedBundleIdentifier = value
        case "--title-class": expectedTitleClass = WindowTitleClass(rawValue: value)
        case "--duration": durationSeconds = Double(value) ?? .nan
        case "--threshold-dbfs": thresholdDBFS = Double(value) ?? .nan
        case "--report": reportPath = value
        default: usage()
        }
    }

    guard let processID, processID > 0,
          let windowID, windowID > 0,
          let expectedApplicationName, !expectedApplicationName.isEmpty,
          let expectedTitleClass,
          durationSeconds.isFinite, durationSeconds >= 2, durationSeconds <= 60,
          thresholdDBFS.isFinite, thresholdDBFS >= -120, thresholdDBFS <= -1,
          let reportPath, !reportPath.isEmpty else {
        usage()
    }

    return Options(
        processID: processID,
        windowID: windowID,
        expectedApplicationName: expectedApplicationName,
        expectedBundleIdentifier: expectedBundleIdentifier,
        expectedTitleClass: expectedTitleClass,
        durationSeconds: durationSeconds,
        thresholdDBFS: thresholdDBFS,
        reportPath: reportPath
    )
}

private func classifyWindowTitle(_ title: String?) -> WindowTitleClass {
    guard let title, !title.isEmpty else { return .absent }
    let folded = title.folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
    )
    if folded.contains("skyrim") { return .skyrim }
    if folded.contains("steam") { return .steam }
    return .generic
}

private func wait(
    _ semaphore: DispatchSemaphore,
    timeoutSeconds: Double,
    failure: String
) {
    guard waitForSignal(semaphore, timeoutSeconds: timeoutSeconds) else {
        fail(failure, code: 124)
    }
}

private func waitForSignal(_ semaphore: DispatchSemaphore, timeoutSeconds: Double) -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)

    while Date() < deadline {
        if semaphore.wait(timeout: .now() + 0.05) == .success { return true }
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return false
}

private func result(for snapshot: AudioLevelSnapshot, streamError: Bool) -> String {
    if streamError { return "STREAM_ERROR" }
    if snapshot.formatChangeCount > 0 { return "PCM_FORMAT_CHANGED" }
    if snapshot.malformedBufferCount > 0 { return "PCM_BUFFER_MALFORMED" }
    if snapshot.audioBufferCount == 0 || snapshot.scalarSampleCount == 0 { return "NO_PCM_DATA" }
    if snapshot.nonSilentSampleCount == 0 { return "SILENT_AT_THRESHOLD" }
    return "NON_SILENT_PCM"
}

private func buildReport(
    options: Options,
    snapshot: AudioLevelSnapshot,
    elapsedSeconds: Double,
    stopTimedOut: Bool,
    streamError: Bool,
    bundleIdentifierChecked: Bool
) -> String {
    let nonSilentRatio = snapshot.scalarSampleCount == 0
        ? 0
        : Double(snapshot.nonSilentSampleCount) / Double(snapshot.scalarSampleCount)
    let clippingRatio = snapshot.scalarSampleCount == 0
        ? 0
        : Double(snapshot.clippedSampleCount) / Double(snapshot.scalarSampleCount)
    let sampleRate = snapshot.format?.sampleRateHz ?? 0
    let channels = snapshot.format?.channelCount ?? 0

    return [
        "SECUNDA_SCK_AUDIO_LEVEL_FORMAT=1",
        "METHOD=screencapturekit-audio-only-exact-window-filter",
        "CAPTURE_RESULT=\(result(for: snapshot, streamError: streamError))",
        "TARGET_PROCESS_ID=\(options.processID)",
        "TARGET_WINDOW_ID=\(options.windowID)",
        "TARGET_PROCESS_MATCH=1",
        "TARGET_WINDOW_MATCH=1",
        "TARGET_APPLICATION_NAME_MATCH=1",
        "TARGET_BUNDLE_IDENTIFIER_MATCH=\(bundleIdentifierChecked ? "1" : "NOT_REQUESTED")",
        "TARGET_TITLE_CLASS=\(options.expectedTitleClass.rawValue)",
        "TARGET_TITLE_CLASS_MATCH=1",
        "TARGET_WINDOW_ONSCREEN=1",
        "REQUESTED_DURATION_SECONDS=\(fixedAudioMetric(options.durationSeconds))",
        "CAPTURE_ELAPSED_SECONDS=\(fixedAudioMetric(elapsedSeconds))",
        "PCM_DURATION_SECONDS=\(fixedAudioMetric(snapshot.pcmDurationSeconds))",
        "SAMPLE_RATE_HZ=\(sampleRate)",
        "CHANNEL_COUNT=\(channels)",
        "PCM_ENCODING=\(snapshot.format?.encoding.rawValue ?? "unknown")",
        "THRESHOLD_DBFS=\(fixedAudioMetric(options.thresholdDBFS))",
        "AUDIO_BUFFER_COUNT=\(snapshot.audioBufferCount)",
        "AUDIO_FRAME_COUNT=\(snapshot.audioFrameCount)",
        "SCALAR_SAMPLE_COUNT=\(snapshot.scalarSampleCount)",
        "NON_SILENT_BUFFER_COUNT=\(snapshot.nonSilentBufferCount)",
        "NON_SILENT_SAMPLE_COUNT=\(snapshot.nonSilentSampleCount)",
        "NON_SILENT_SAMPLE_RATIO=\(fixedAudioMetric(nonSilentRatio))",
        "RMS_DBFS=\(levelDBFS(snapshot.rmsMagnitude))",
        "PEAK_DBFS=\(levelDBFS(snapshot.peakMagnitude))",
        "CLIPPED_SAMPLE_COUNT=\(snapshot.clippedSampleCount)",
        "CLIPPED_SAMPLE_RATIO=\(fixedAudioMetric(clippingRatio))",
        "INVALID_SAMPLE_COUNT=\(snapshot.invalidSampleCount)",
        "MALFORMED_BUFFER_COUNT=\(snapshot.malformedBufferCount)",
        "FORMAT_CHANGE_COUNT=\(snapshot.formatChangeCount)",
        "STOP_RESULT=\(stopTimedOut ? "TIMEOUT" : "STOPPED")",
        "PIXEL_STREAM_OUTPUT_COUNT=0",
        "PIXELS_RECEIVED_OR_STORED=0",
        "PCM_WRITTEN_TO_STORAGE=0",
        "OUTPUT_VOLUME_OR_MUTE_CHANGED=0",
        "RAW_TITLES_APP_NAMES_BUNDLE_IDS_OMITTED=1",
        "FILTER_SCOPE=selected-window-owning-application-audio",
        "OTHER_APPLICATION_AUDIO_EXCLUDED=1",
        "LIMITATION_1=audio-filtering-is-application-level-not-window-level",
        "LIMITATION_2=same-native-application-audio-may-be-mixed",
        "LIMITATION_3=wine-audio-may-originate-from-a-different-native-process",
        "LIMITATION_4=non-silent-pcm-proves-signal-not-perceived-quality",
        "LIMITATION_5=screen-recording-user-consent-is-required",
    ].joined(separator: "\n") + "\n"
}

private func writeReport(_ report: String, to path: String) {
    do {
        try Data(report.utf8).write(
            to: URL(fileURLWithPath: path),
            options: .atomic
        )
    } catch {
        fail("unable to write the aggregate report", code: 73)
    }
}

private func runSelfTest() -> Never {
    var accumulator = AudioLevelAccumulator()
    let format = PCMFormatIdentity(
        streamDescription: AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    )!
    let threshold = pow(10.0, -60.0 / 20.0)
    var silent = AudioLevelDelta()
    [0.0, 0.0, 0.0, 0.0].forEach { silent.observe($0, thresholdLinear: threshold) }
    accumulator.record(silent, frameCount: 2, format: format)

    var signal = AudioLevelDelta()
    [0.5, -0.5, 0.25, -0.25].forEach { signal.observe($0, thresholdLinear: threshold) }
    accumulator.record(signal, frameCount: 2, format: format)
    let snapshot = accumulator.snapshot()

    let checks = [
        snapshot.audioBufferCount == 2,
        snapshot.audioFrameCount == 4,
        snapshot.scalarSampleCount == 8,
        snapshot.nonSilentBufferCount == 1,
        snapshot.nonSilentSampleCount == 4,
        abs(snapshot.pcmDurationSeconds - (4.0 / 48_000.0)) < 0.000_001,
        levelDBFS(snapshot.peakMagnitude) == "-6.021",
        classifyWindowTitle("The Elder Scrolls V: Skyrim Special Edition") == .skyrim,
        classifyWindowTitle("private account text") == .generic,
    ]
    guard checks.allSatisfy({ $0 }) else {
        fail("deterministic self-test assertion failed", code: 1)
    }

    let testOptions = Options(
        processID: 4242,
        windowID: 77,
        expectedApplicationName: "do-not-emit-app-name",
        expectedBundleIdentifier: "do.not.emit.bundle",
        expectedTitleClass: .skyrim,
        durationSeconds: 10,
        thresholdDBFS: -60,
        reportPath: "/not/used"
    )
    let report = buildReport(
        options: testOptions,
        snapshot: snapshot,
        elapsedSeconds: 10,
        stopTimedOut: false,
        streamError: false,
        bundleIdentifierChecked: true
    )
    guard report.contains("CAPTURE_RESULT=NON_SILENT_PCM"),
          report.contains("PIXEL_STREAM_OUTPUT_COUNT=0"),
          !report.contains(testOptions.expectedApplicationName),
          !report.contains(testOptions.expectedBundleIdentifier!) else {
        fail("sanitized report self-test failed", code: 1)
    }

    print("PASS: audio statistics, identity classification, and report redaction are deterministic.")
    exit(0)
}

private func runMain() {
    let arguments = CommandLine.arguments.dropFirst()
    if Array(arguments) == ["--self-test"] {
        runSelfTest()
    }
    if Array(arguments) == ["--help"] || Array(arguments) == ["-h"] {
        usage()
    }
    let options = parseOptions(arguments)
    guard kill(options.processID, 0) == 0 || errno == EPERM else {
        fail("target PID is not running", code: 66)
    }

    let watchdog = HardWatchdog(timeoutSeconds: options.durationSeconds + 30)
    defer { watchdog.cancel() }

    guard CGPreflightScreenCaptureAccess() else {
        fail(
            "Screen Recording permission is not already granted; no access request was made",
            code: 77
        )
    }
    _ = NSApplication.shared.setActivationPolicy(.prohibited)

    let contentSemaphore = DispatchSemaphore(value: 0)
    var shareableContent: SCShareableContent?
    var contentFailed = false
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
        shareableContent = content
        contentFailed = error != nil
        contentSemaphore.signal()
    }
    wait(
        contentSemaphore,
        timeoutSeconds: 10,
        failure: "shareable-content discovery timed out"
    )
    guard !contentFailed, let shareableContent else {
        fail("shareable-content discovery was denied or failed", code: 69)
    }

    guard let window = shareableContent.windows.first(where: {
        $0.windowID == options.windowID
            && $0.owningApplication?.processID == options.processID
            && $0.isOnScreen
    }), let application = window.owningApplication else {
        fail("exact onscreen window does not belong to the requested PID", code: 66)
    }
    guard application.applicationName == options.expectedApplicationName else {
        fail("owning application name did not match the expected identity", code: 66)
    }
    guard classifyWindowTitle(window.title) == options.expectedTitleClass else {
        fail("window title class did not match the expected identity", code: 66)
    }
    if let expectedBundleIdentifier = options.expectedBundleIdentifier {
        guard application.bundleIdentifier == expectedBundleIdentifier else {
            fail("owning bundle identifier did not match the expected identity", code: 66)
        }
    }

    let thresholdLinear = pow(10.0, options.thresholdDBFS / 20.0)
    let collector = AudioCollector(thresholdLinear: thresholdLinear)
    let configuration = SCStreamConfiguration()
    configuration.capturesAudio = true
    configuration.excludesCurrentProcessAudio = true
    configuration.sampleRate = 48_000
    configuration.channelCount = 2
    configuration.showsCursor = false
    configuration.queueDepth = 1

    let filter = SCContentFilter(desktopIndependentWindow: window)
    let stream = SCStream(filter: filter, configuration: configuration, delegate: collector)
    let audioQueue = DispatchQueue(label: "com.secunda.audio-sck-level", qos: .userInitiated)
    do {
        try stream.addStreamOutput(collector, type: .audio, sampleHandlerQueue: audioQueue)
    } catch {
        fail("could not register the audio-only stream output", code: 69)
    }

    let startSemaphore = DispatchSemaphore(value: 0)
    var captureStartFailed = false
    stream.startCapture { error in
        captureStartFailed = error != nil
        startSemaphore.signal()
    }
    wait(startSemaphore, timeoutSeconds: 10, failure: "capture start timed out")
    guard !captureStartFailed else {
        fail("capture start was denied or failed", code: 69)
    }

    let startedAt = ProcessInfo.processInfo.systemUptime
    _ = DispatchSemaphore(value: 0).wait(timeout: .now() + options.durationSeconds)
    let captureElapsed = ProcessInfo.processInfo.systemUptime - startedAt

    let stopSemaphore = DispatchSemaphore(value: 0)
    var captureStopFailed = false
    stream.stopCapture { error in
        captureStopFailed = error != nil
        stopSemaphore.signal()
    }
    let stopTimedOut = !waitForSignal(stopSemaphore, timeoutSeconds: 5)
    let snapshot = collector.snapshot()

    let report = buildReport(
        options: options,
        snapshot: snapshot.levels,
        elapsedSeconds: captureElapsed,
        stopTimedOut: stopTimedOut,
        streamError: snapshot.streamError || captureStopFailed || stopTimedOut,
        bundleIdentifierChecked: options.expectedBundleIdentifier != nil
    )
    writeReport(report, to: options.reportPath)

    if stopTimedOut {
        fail("capture stop timed out; the process is exiting to release the stream", code: 124)
    }
}

@main
private struct AudioSCKLevelProbe {
    static func main() {
        runMain()
    }
}
