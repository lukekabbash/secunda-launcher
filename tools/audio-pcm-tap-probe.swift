import CoreAudio
import CoreGraphics
import AudioToolbox
import Darwin
import Foundation

private let environmentSelfTestArgument = "--environment-isolation-worker"
private let environmentSentinelKey = "SECUNDA_AUDIO_PCM_PROBE_UNRELATED_SENTINEL"
private let workerParentPIDKey = "SECUNDA_AUDIO_PCM_PROBE_PARENT_PID"
private let workerRunTokenKey = "SECUNDA_AUDIO_PCM_PROBE_RUN_TOKEN"

private func currentExecutableURL() -> URL {
    let executablePath = CommandLine.arguments[0]
    if executablePath.hasPrefix("/") {
        return URL(fileURLWithPath: executablePath)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(executablePath)
}

private func minimalWorkerEnvironment(
    inherited: [String: String],
    parentPID: pid_t,
    runToken: String
) -> [String: String] {
    let allowedKeys: Set<String> = ["HOME", "LANG", "PATH", "TMPDIR"]
    var environment = inherited.filter { key, _ in
        allowedKeys.contains(key) || key.hasPrefix("LC_")
    }
    environment[workerParentPIDKey] = String(parentPID)
    environment[workerRunTokenKey] = runToken
    return environment
}

private func runEnvironmentIsolationWorker() -> Never {
    let environment = ProcessInfo.processInfo.environment
    let expectedParentPID = environment[workerParentPIDKey].flatMap(pid_t.init)
    let hasValidRunToken = environment[workerRunTokenKey].flatMap(UUID.init(uuidString:)) != nil
    let passed = environment[environmentSentinelKey] == nil
        && expectedParentPID == getppid()
        && hasValidRunToken
    exit(passed ? 0 : 1)
}

private func environmentIsolationSelfTest() -> Bool {
    var inherited = ProcessInfo.processInfo.environment
    inherited[environmentSentinelKey] = "must-not-cross-worker-boundary"

    let worker = Process()
    worker.executableURL = currentExecutableURL()
    worker.arguments = [environmentSelfTestArgument]
    worker.environment = minimalWorkerEnvironment(
        inherited: inherited,
        parentPID: getpid(),
        runToken: UUID().uuidString
    )
    worker.standardOutput = FileHandle.nullDevice
    worker.standardError = FileHandle.nullDevice

    let completion = DispatchSemaphore(value: 0)
    worker.terminationHandler = { _ in completion.signal() }
    do {
        try worker.run()
    } catch {
        return false
    }
    guard completion.wait(timeout: .now() + 2) == .success else {
        worker.terminate()
        return false
    }
    return worker.terminationReason == .exit && worker.terminationStatus == 0
}

private func parseConfiguration(_ arguments: [String]) throws -> Configuration? {
    enum ArgumentError: Error { case invalid }
    if arguments == ["--self-test"] {
        runSelfTest()
        return nil
    }
    if arguments == ["--help"] || arguments == ["-h"] {
        printUsage()
        return nil
    }

    var targetPID: pid_t?
    var seconds = 5.0
    var threshold: Float = 0.000_000_1
    var minimumNonzeroSamples: UInt64 = 64
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        guard index + 1 < arguments.count else { throw ArgumentError.invalid }
        let value = arguments[index + 1]
        switch argument {
        case "--pid":
            guard let parsed = pid_t(value), parsed > 0, targetPID == nil else {
                throw ArgumentError.invalid
            }
            targetPID = parsed
        case "--seconds":
            guard let parsed = Double(value), parsed >= 0.25, parsed <= 60 else {
                throw ArgumentError.invalid
            }
            seconds = parsed
        case "--nonzero-threshold":
            guard let parsed = Float(value), parsed.isFinite, parsed >= 0, parsed <= 1 else {
                throw ArgumentError.invalid
            }
            threshold = parsed
        case "--minimum-nonzero-samples":
            guard let parsed = UInt64(value), parsed > 0 else {
                throw ArgumentError.invalid
            }
            minimumNonzeroSamples = parsed
        default:
            throw ArgumentError.invalid
        }
        index += 2
    }
    guard let targetPID else { throw ArgumentError.invalid }
    return Configuration(
        pid: targetPID,
        seconds: seconds,
        nonzeroThreshold: threshold,
        minimumNonzeroSamples: minimumNonzeroSamples
    )
}

private func printUsage() {
    let usage = """
    Usage:
      ./build/tools/audio-pcm-tap-probe --pid PID [options]
      ./build/tools/audio-pcm-tap-probe --self-test

    Options:
      --seconds N                    Capture duration, 0.25...60 (default: 5)
      --nonzero-threshold N          Absolute PCM threshold, 0...1 (default: 1e-7)
      --minimum-nonzero-samples N    Samples above threshold required (default: 64)

    The probe targets exactly one existing CoreAudio process and emits only JSON
    level statistics. It stores no audio. The tap does not mute the target, and
    the probe never reads or changes endpoint speaker mute or volume state.

    Safety: the probe calls only the non-requesting permission preflight. If the
    launcher's capture permission is not already granted, it exits before creating
    or starting a tap so macOS cannot display a first-use permission prompt.

    Exit 0: non-silent PCM observed. Exit 1: tap ran but non-silent PCM was not
    proven. Exit 3: capture permission was not already granted. Exit 4: setup
    failure. Exit 5: PID is not an active CoreAudio client.
    """
    FileHandle.standardError.write(Data((usage + "\n").utf8))
}

private func runSelfTest() {
    let meter = PCMMeter(threshold: 0.01)
    meter.recordSynthetic([0, 0.5, -0.5, 1, .nan])
    let result = meter.snapshot()
    let expectedRMS = sqrt(1.5 / 4.0)
    let runToken = "11111111-2222-3333-4444-555555555555"
    let identity = probeObjectIdentity(runToken: runToken)
    guard result.sampleValues == 5,
          result.finiteSamples == 4,
          result.nonzeroSamples == 3,
          result.nonfiniteSamples == 1,
          abs(result.peak - 1) < 0.000_001,
          abs(result.rms - expectedRMS) < 0.000_001,
          identity.aggregateUID.hasSuffix(runToken),
          identity.tapUID == runToken,
          identity.aggregateName != identity.tapName,
          environmentIsolationSelfTest() else {
        FileHandle.standardError.write(Data("audio-pcm-tap-probe: self-test failed\n".utf8))
        exit(1)
    }
    print("audio-pcm-tap-probe: self-test passed")
}

private func makeFormatReport(_ format: AudioStreamBasicDescription) -> FormatReport {
    FormatReport(
        sampleRate: format.mSampleRate,
        channels: format.mChannelsPerFrame,
        bitsPerChannel: format.mBitsPerChannel,
        bytesPerFrame: format.mBytesPerFrame,
        isFloat: format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
        isNonInterleaved: format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
    )
}

private func capture(_ configuration: Configuration, runToken: String) throws -> ProbeReport {
    guard #available(macOS 14.2, *) else {
        throw ProbeFailure(
            result: "fail-unsupported-os",
            stage: "os-version",
            message: "CoreAudio process taps require macOS 14.2 or newer.",
            status: nil,
            exitCode: 4
        )
    }
    guard kill(configuration.pid, 0) == 0 || errno == EPERM else {
        throw ProbeFailure(
            result: "fail-process-not-running",
            stage: "target-validation",
            message: "The target PID is not running.",
            status: nil,
            exitCode: 5
        )
    }

    guard CGPreflightScreenCaptureAccess() else {
        throw ProbeFailure(
            result: "fail-permission-not-pregranted",
            stage: "permission-preflight",
            message: "Capture permission is not already granted; the probe refused to start so no permission prompt was requested.",
            status: nil,
            exitCode: 3
        )
    }
    guard let processAudioObjectID = processAudioObjectID(for: configuration.pid) else {
        throw ProbeFailure(
            result: "fail-no-coreaudio-client",
            stage: "target-translation",
            message: "The target PID is not currently registered as a CoreAudio client.",
            status: nil,
            exitCode: 5
        )
    }

    let meter = PCMMeter(threshold: configuration.nonzeroThreshold)
    let session = TapSession(runToken: runToken)
    let format = try session.createTap(for: processAudioObjectID)
    try session.createAggregateDevice()
    try session.configureCapture(tapFormat: format, meter: meter)
    try session.start()
    Thread.sleep(forTimeInterval: configuration.seconds)
    try session.stop()
    let snapshot = meter.snapshot()
    session.close()

    let passed = snapshot.nonzeroSamples >= configuration.minimumNonzeroSamples
        && snapshot.peak > Double(configuration.nonzeroThreshold)
    let result: String
    let interpretation: String
    if passed {
        result = "pass-nonzero-pcm"
        interpretation = "The exact target process supplied non-silent PCM to a pre-endpoint CoreAudio tap. Endpoint mute does not make these captured samples nonzero."
    } else if snapshot.dataCallbacks == 0 || snapshot.sampleValues == 0 {
        result = "fail-no-pcm-callbacks"
        interpretation = "The tap started, but no PCM buffers arrived during the measurement window."
    } else {
        result = "fail-silent-pcm"
        interpretation = "PCM buffers arrived, but they did not contain enough samples above the configured threshold to prove non-silent output."
    }

    return ProbeReport(
        schema: "secunda.coreaudio-pcm-tap-probe.v1",
        generatedAtUTC: ISO8601DateFormatter().string(from: Date()),
        targetPID: configuration.pid,
        processName: processName(configuration.pid),
        processAudioObjectID: processAudioObjectID,
        durationSeconds: configuration.seconds,
        permissionPreflight: "granted-before-tap",
        capturePosition: "process-output-before-hardware-endpoint",
        tapMuteBehavior: "tap-does-not-mute-target",
        endpointMuteOrVolumeAccess: "never-read-or-changed",
        rawAudioStored: false,
        format: makeFormatReport(format),
        callbacks: snapshot.callbacks,
        dataCallbacks: snapshot.dataCallbacks,
        buffers: snapshot.buffers,
        frames: snapshot.frames,
        sampleValues: snapshot.sampleValues,
        finiteSamples: snapshot.finiteSamples,
        nonzeroSamples: snapshot.nonzeroSamples,
        nonfiniteSamples: snapshot.nonfiniteSamples,
        nonzeroThreshold: configuration.nonzeroThreshold,
        minimumNonzeroSamples: configuration.minimumNonzeroSamples,
        rms: snapshot.rms,
        peak: snapshot.peak,
        result: result,
        interpretation: interpretation
    )
}

private func runSupervisedWorker(
    arguments: [String],
    configuration: Configuration
) throws -> WorkerResult {
    let worker = Process()
    worker.executableURL = currentExecutableURL()
    worker.arguments = arguments
    let runToken = UUID().uuidString
    worker.environment = minimalWorkerEnvironment(
        inherited: ProcessInfo.processInfo.environment,
        parentPID: getpid(),
        runToken: runToken
    )

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    worker.standardOutput = outputPipe
    worker.standardError = errorPipe

    let completion = DispatchSemaphore(value: 0)
    worker.terminationHandler = { _ in completion.signal() }
    do {
        try worker.run()
    } catch {
        throw ProbeFailure(
            result: "fail-worker-launch",
            stage: "launch-coreaudio-worker",
            message: "The isolated CoreAudio worker could not be launched: \(error.localizedDescription)",
            status: nil,
            exitCode: 4
        )
    }

    let setupAllowance = 6.0
    let deadline = DispatchTime.now() + configuration.seconds + setupAllowance
    guard completion.wait(timeout: deadline) == .success else {
        worker.terminate()
        if completion.wait(timeout: .now() + 1) == .timedOut {
            kill(worker.processIdentifier, SIGKILL)
            _ = completion.wait(timeout: .now() + 1)
        }
        let cleanupResult = cleanupAudioObjects(runToken: runToken)
        throw ProbeFailure(
            result: "fail-coreaudio-io-handshake-timeout",
            stage: "coreaudio-io-handshake",
            message: "CoreAudio did not complete the process-tap I/O handshake within the bounded setup window. The isolated worker was terminated; no PCM result is claimed. \(cleanupResult.summary)",
            status: nil,
            exitCode: 4
        )
    }

    let result = WorkerResult(
        standardOutput: outputPipe.fileHandleForReading.readDataToEndOfFile(),
        standardError: errorPipe.fileHandleForReading.readDataToEndOfFile(),
        exitCode: worker.terminationStatus
    )
    let cleanupResult = cleanupAudioObjects(runToken: runToken)
    guard cleanupResult.succeeded else {
        throw ProbeFailure(
            result: "fail-coreaudio-cleanup",
            stage: "cleanup-coreaudio-objects",
            message: cleanupResult.summary,
            status: nil,
            exitCode: 4
        )
    }
    return result
}

private func encode<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

@main
private enum AudioPCMTapProbe {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == [environmentSelfTestArgument] {
                runEnvironmentIsolationWorker()
            }
            let expectedParentPID = ProcessInfo.processInfo.environment[workerParentPIDKey]
                .flatMap(pid_t.init)
            let isCoreAudioWorker = expectedParentPID == getppid()
            let runToken = ProcessInfo.processInfo.environment[workerRunTokenKey]
                .flatMap { UUID(uuidString: $0)?.uuidString }
            guard let configuration = try parseConfiguration(arguments) else {
                exit(0)
            }

            if !isCoreAudioWorker {
                let workerResult = try runSupervisedWorker(
                    arguments: arguments,
                    configuration: configuration
                )
                FileHandle.standardOutput.write(workerResult.standardOutput)
                FileHandle.standardError.write(workerResult.standardError)
                exit(workerResult.exitCode)
            }

            guard let runToken else {
                throw ProbeFailure(
                    result: "fail-worker-identity",
                    stage: "validate-coreaudio-worker",
                    message: "The CoreAudio worker did not receive a valid run identity.",
                    status: nil,
                    exitCode: 4
                )
            }
            let report = try capture(configuration, runToken: runToken)
            print(try encode(report))
            exit(report.result == "pass-nonzero-pcm" ? 0 : 1)
        } catch let failure as ProbeFailure {
            let pidArgument: pid_t? = CommandLine.arguments.firstIndex(of: "--pid").flatMap { index in
                let valueIndex = CommandLine.arguments.index(after: index)
                guard valueIndex < CommandLine.arguments.endIndex else { return nil }
                return pid_t(CommandLine.arguments[valueIndex])
            }
            let report = FailureReport(
                schema: "secunda.coreaudio-pcm-tap-probe.v1",
                generatedAtUTC: ISO8601DateFormatter().string(from: Date()),
                targetPID: pidArgument,
                result: failure.result,
                stage: failure.stage,
                message: failure.message,
                osStatus: failure.status,
                permissionPromptAttempted: false
            )
            if let output = try? encode(report) {
                print(output)
            }
            exit(failure.exitCode)
        } catch {
            FileHandle.standardError.write(Data("audio-pcm-tap-probe: invalid arguments\n".utf8))
            printUsage()
            exit(2)
        }
    }
}
