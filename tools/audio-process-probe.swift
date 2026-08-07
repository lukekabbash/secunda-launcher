#!/usr/bin/env swift

import CoreAudio
import Darwin
import Foundation

private let systemAudioObject = AudioObjectID(kAudioObjectSystemObject)

private struct Configuration {
    var pids: [pid_t] = []
    var listClients = false
    var seconds = 8.0
    var intervalMilliseconds = 250
    var minimumActiveSamples = 3
}

private struct DeviceReport: Codable {
    let id: AudioObjectID
    let name: String?
    let isDefaultOutput: Bool
    let isAlive: Bool?
    let isRunning: Bool?
    let isMuted: Bool?
    let volumeScalar: Float?
    let nominalSampleRate: Double?
}

private struct TargetReport: Codable {
    let pid: pid_t
    let processName: String?
    let audioObjectID: AudioObjectID?
    let samples: Int
    let connectedSamples: Int
    let runningIOSamples: Int
    let runningOutputSamples: Int
    let longestActiveOutputRun: Int
    let outputDevices: [DeviceReport]
    let result: String
}

private struct ProbeReport: Codable {
    let schema: String
    let generatedAtUTC: String
    let osVersion: String
    let mode: String
    let durationSeconds: Double
    let intervalMilliseconds: Int
    let minimumActiveSamples: Int
    let pathEstablished: Bool
    let targets: [TargetReport]
    let interpretation: String
    let humanHearingStillRequired: Bool
}

private struct SampleState {
    var audioObjectID: AudioObjectID?
    var samples = 0
    var connectedSamples = 0
    var runningIOSamples = 0
    var runningOutputSamples = 0
    var currentActiveOutputRun = 0
    var longestActiveOutputRun = 0
    var deviceIDs = Set<AudioObjectID>()

    mutating func record(audioObjectID: AudioObjectID?) {
        samples += 1
        guard let audioObjectID else {
            currentActiveOutputRun = 0
            return
        }

        self.audioObjectID = audioObjectID
        connectedSamples += 1
        if readUInt32(audioObjectID, selector: kAudioProcessPropertyIsRunning) == 1 {
            runningIOSamples += 1
        }

        let outputIsRunning = readUInt32(
            audioObjectID,
            selector: kAudioProcessPropertyIsRunningOutput
        ) == 1
        if outputIsRunning {
            runningOutputSamples += 1
            currentActiveOutputRun += 1
            longestActiveOutputRun = max(longestActiveOutputRun, currentActiveOutputRun)
        } else {
            currentActiveOutputRun = 0
        }

        readArray(
            audioObjectID,
            selector: kAudioProcessPropertyDevices,
            scope: kAudioObjectPropertyScopeOutput,
            as: AudioObjectID.self
        ).forEach { deviceIDs.insert($0) }
    }
}

private func address(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
}

private func readScalar<T>(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    as type: T.Type
) -> T? {
    var propertyAddress = address(selector, scope: scope)
    guard AudioObjectHasProperty(objectID, &propertyAddress) else { return nil }

    let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { value.deallocate() }
    var size = UInt32(MemoryLayout<T>.size)
    let status = AudioObjectGetPropertyData(
        objectID,
        &propertyAddress,
        0,
        nil,
        &size,
        value
    )
    guard status == noErr, size == MemoryLayout<T>.size else { return nil }
    return value.move()
}

private func readUInt32(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> UInt32? {
    readScalar(objectID, selector: selector, scope: scope, as: UInt32.self)
}

private func readArray<T>(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    as type: T.Type
) -> [T] {
    var propertyAddress = address(selector, scope: scope)
    guard AudioObjectHasProperty(objectID, &propertyAddress) else { return [] }

    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(objectID, &propertyAddress, 0, nil, &size) == noErr,
          size > 0 else { return [] }

    let count = Int(size) / MemoryLayout<T>.stride
    let values = UnsafeMutablePointer<T>.allocate(capacity: count)
    defer { values.deallocate() }
    guard AudioObjectGetPropertyData(
        objectID,
        &propertyAddress,
        0,
        nil,
        &size,
        values
    ) == noErr else { return [] }
    return Array(UnsafeBufferPointer(start: values, count: count))
}

private func readString(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> String? {
    var propertyAddress = address(selector, scope: scope)
    guard AudioObjectHasProperty(objectID, &propertyAddress) else { return nil }

    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(
        objectID,
        &propertyAddress,
        0,
        nil,
        &size,
        &value
    )
    guard status == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
}

private func audioObjectID(for pid: pid_t) -> AudioObjectID? {
    var propertyAddress = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var qualifier = pid
    var result = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafePointer(to: &qualifier) { qualifierPointer in
        AudioObjectGetPropertyData(
            systemAudioObject,
            &propertyAddress,
            UInt32(MemoryLayout<pid_t>.size),
            qualifierPointer,
            &size,
            &result
        )
    }
    return status == noErr && result != kAudioObjectUnknown ? result : nil
}

private func processName(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 2 * (Int(MAXCOMLEN) + 1))
    let length = proc_name(pid, &buffer, UInt32(buffer.count))
    return length > 0 ? String(cString: buffer) : nil
}

private func defaultOutputDeviceID() -> AudioObjectID? {
    readScalar(
        systemAudioObject,
        selector: kAudioHardwarePropertyDefaultOutputDevice,
        as: AudioObjectID.self
    )
}

private func deviceReport(_ id: AudioObjectID, defaultOutputID: AudioObjectID?) -> DeviceReport {
    DeviceReport(
        id: id,
        name: readString(id, selector: kAudioObjectPropertyName),
        isDefaultOutput: id == defaultOutputID,
        isAlive: readUInt32(id, selector: kAudioDevicePropertyDeviceIsAlive).map { $0 != 0 },
        isRunning: readUInt32(id, selector: kAudioDevicePropertyDeviceIsRunning).map { $0 != 0 },
        isMuted: readUInt32(
            id,
            selector: kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput
        ).map { $0 != 0 },
        volumeScalar: readScalar(
            id,
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput,
            as: Float.self
        ),
        nominalSampleRate: readScalar(
            id,
            selector: kAudioDevicePropertyNominalSampleRate,
            as: Double.self
        )
    )
}

private func allAudioClientPIDs() -> [pid_t] {
    let processObjects = readArray(
        systemAudioObject,
        selector: kAudioHardwarePropertyProcessObjectList,
        as: AudioObjectID.self
    )
    return processObjects.compactMap {
        readScalar($0, selector: kAudioProcessPropertyPID, as: pid_t.self)
    }.sorted()
}

private func result(for state: SampleState, minimumActiveSamples: Int) -> String {
    guard state.connectedSamples > 0 else { return "fail-no-coreaudio-client" }
    guard state.runningOutputSamples >= minimumActiveSamples else {
        return state.runningOutputSamples == 0
            ? "fail-no-active-output"
            : "fail-insufficient-active-output"
    }
    return "pass-active-coreaudio-output"
}

private func parseConfiguration(_ arguments: [String]) throws -> Configuration {
    enum ArgumentError: Error { case invalid(String) }
    var configuration = Configuration()
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--list":
            configuration.listClients = true
        case "--pid", "--seconds", "--interval-ms", "--minimum-active-samples":
            guard index + 1 < arguments.count else { throw ArgumentError.invalid(argument) }
            let value = arguments[index + 1]
            switch argument {
            case "--pid":
                guard let pid = pid_t(value), pid > 0 else { throw ArgumentError.invalid(value) }
                configuration.pids.append(pid)
            case "--seconds":
                guard let seconds = Double(value), seconds >= 0, seconds <= 300 else {
                    throw ArgumentError.invalid(value)
                }
                configuration.seconds = seconds
            case "--interval-ms":
                guard let milliseconds = Int(value), milliseconds >= 50, milliseconds <= 10_000 else {
                    throw ArgumentError.invalid(value)
                }
                configuration.intervalMilliseconds = milliseconds
            default:
                guard let samples = Int(value), samples > 0 else {
                    throw ArgumentError.invalid(value)
                }
                configuration.minimumActiveSamples = samples
            }
            index += 1
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw ArgumentError.invalid(argument)
        }
        index += 1
    }

    if configuration.listClients {
        configuration.pids = allAudioClientPIDs()
        configuration.seconds = 0
        configuration.minimumActiveSamples = 1
    }
    guard !configuration.pids.isEmpty else { throw ArgumentError.invalid("missing --pid or --list") }
    return configuration
}

private func printUsage() {
    let usage = """
    Usage:
      swift tools/audio-process-probe.swift --pid PID [--pid PID ...] [options]
      swift tools/audio-process-probe.swift --list

    Options:
      --seconds N                 Sample duration, 0...300 (default: 8)
      --interval-ms N             Sampling interval, 50...10000 (default: 250)
      --minimum-active-samples N  Required active-output samples (default: 3)

    The probe reads CoreAudio process state only. It never records or redirects audio.
    Exit 0 means at least one requested PID sustained active CoreAudio output.
    """
    FileHandle.standardError.write(Data((usage + "\n").utf8))
}

private func sample(_ configuration: Configuration) -> ProbeReport {
    var states = Dictionary(uniqueKeysWithValues: configuration.pids.map { ($0, SampleState()) })
    let interval = Double(configuration.intervalMilliseconds) / 1_000.0
    let sampleCount = max(1, Int(floor(configuration.seconds / interval)) + 1)

    for sampleIndex in 0..<sampleCount {
        for pid in configuration.pids {
            states[pid]?.record(audioObjectID: audioObjectID(for: pid))
        }
        if sampleIndex + 1 < sampleCount {
            Thread.sleep(forTimeInterval: interval)
        }
    }

    let defaultOutputID = defaultOutputDeviceID()
    let targets = configuration.pids.sorted().map { pid -> TargetReport in
        let state = states[pid] ?? SampleState()
        return TargetReport(
            pid: pid,
            processName: processName(pid),
            audioObjectID: state.audioObjectID,
            samples: state.samples,
            connectedSamples: state.connectedSamples,
            runningIOSamples: state.runningIOSamples,
            runningOutputSamples: state.runningOutputSamples,
            longestActiveOutputRun: state.longestActiveOutputRun,
            outputDevices: state.deviceIDs.sorted().map {
                deviceReport($0, defaultOutputID: defaultOutputID)
            },
            result: result(for: state, minimumActiveSamples: configuration.minimumActiveSamples)
        )
    }
    let established = targets.contains { $0.result == "pass-active-coreaudio-output" }
    return ProbeReport(
        schema: "secunda.coreaudio-process-probe.v1",
        generatedAtUTC: ISO8601DateFormatter().string(from: Date()),
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        mode: configuration.listClients ? "audio-client-snapshot" : "targeted-sample",
        durationSeconds: configuration.seconds,
        intervalMilliseconds: configuration.intervalMilliseconds,
        minimumActiveSamples: configuration.minimumActiveSamples,
        pathEstablished: established,
        targets: targets,
        interpretation: established
            ? "CoreAudio reports active output streams for at least one target process."
            : "No target met the configured active-output sampling threshold.",
        humanHearingStillRequired: true
    )
}

do {
    let configuration = try parseConfiguration(Array(CommandLine.arguments.dropFirst()))
    let report = sample(configuration)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
    exit(report.pathEstablished || configuration.listClients ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("audio-process-probe: invalid arguments\n".utf8))
    printUsage()
    exit(2)
}
