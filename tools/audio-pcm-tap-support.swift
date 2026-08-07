import CoreAudio
import Darwin
import Foundation

let systemAudioObject = AudioObjectID(kAudioObjectSystemObject)

func propertyAddress(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
}

func readScalar<T>(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    as type: T.Type
) -> T? {
    var address = propertyAddress(selector, scope: scope)
    let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { value.deallocate() }
    var size = UInt32(MemoryLayout<T>.size)
    let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, value)
    guard status == noErr, size == MemoryLayout<T>.size else { return nil }
    return value.move()
}

func readArray<T>(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    as type: T.Type
) -> [T] {
    var address = propertyAddress(selector, scope: scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr,
          size >= MemoryLayout<T>.stride else { return [] }
    let count = Int(size) / MemoryLayout<T>.stride
    let values = UnsafeMutablePointer<T>.allocate(capacity: count)
    defer { values.deallocate() }
    guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, values) == noErr else {
        return []
    }
    return Array(UnsafeBufferPointer(start: values, count: count))
}

struct ProbeObjectIdentity {
    let aggregateName: String
    let aggregateUID: String
    let tapName: String
    let tapUID: String
}

func probeObjectIdentity(runToken: String) -> ProbeObjectIdentity {
    ProbeObjectIdentity(
        aggregateName: "Secunda PCM Probe \(runToken)",
        aggregateUID: "com.secunda.audio-pcm-probe.\(runToken)",
        tapName: "Secunda PCM level probe \(runToken)",
        tapUID: runToken
    )
}

private func translateUID(
    _ uid: String,
    selector: AudioObjectPropertySelector
) -> (id: AudioObjectID, status: OSStatus) {
    var qualifier: CFString = uid as CFString
    var objectID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var address = propertyAddress(selector)
    let status = withUnsafePointer(to: &qualifier) { qualifierPointer in
        AudioObjectGetPropertyData(
            systemAudioObject,
            &address,
            UInt32(MemoryLayout<CFString>.stride),
            qualifierPointer,
            &size,
            &objectID
        )
    }
    return (objectID, status)
}

func cleanupAudioObjects(runToken: String) -> CleanupResult {
    let identity = probeObjectIdentity(runToken: runToken)
    var destroyedAggregates = 0
    var destroyedTaps = 0
    var failures: [String] = []

    let aggregate = translateUID(
        identity.aggregateUID,
        selector: kAudioHardwarePropertyTranslateUIDToDevice
    )
    if aggregate.status != noErr {
        failures.append("translate aggregate UID: \(describe(status: aggregate.status))")
    } else if aggregate.id != kAudioObjectUnknown {
        let destroyStatus = AudioHardwareDestroyAggregateDevice(aggregate.id)
        if destroyStatus == noErr {
            destroyedAggregates += 1
        } else {
            failures.append("aggregate \(aggregate.id): \(describe(status: destroyStatus))")
        }
    }

    let tap = translateUID(
        identity.tapUID,
        selector: kAudioHardwarePropertyTranslateUIDToTap
    )
    if tap.status != noErr {
        failures.append("translate tap UID: \(describe(status: tap.status))")
    } else if tap.id != kAudioObjectUnknown {
        let destroyStatus = AudioHardwareDestroyProcessTap(tap.id)
        if destroyStatus == noErr {
            destroyedTaps += 1
        } else {
            failures.append("tap \(tap.id): \(describe(status: destroyStatus))")
        }
    }

    let residualAggregate = translateUID(
        identity.aggregateUID,
        selector: kAudioHardwarePropertyTranslateUIDToDevice
    )
    let residualTap = translateUID(
        identity.tapUID,
        selector: kAudioHardwarePropertyTranslateUIDToTap
    )
    if residualAggregate.status != noErr {
        failures.append("verify aggregate cleanup: \(describe(status: residualAggregate.status))")
    } else if residualAggregate.id != kAudioObjectUnknown {
        failures.append("residual aggregate \(residualAggregate.id)")
    }
    if residualTap.status != noErr {
        failures.append("verify tap cleanup: \(describe(status: residualTap.status))")
    } else if residualTap.id != kAudioObjectUnknown {
        failures.append("residual tap \(residualTap.id)")
    }

    return CleanupResult(
        destroyedAggregates: destroyedAggregates,
        destroyedTaps: destroyedTaps,
        failures: failures
    )
}

func defaultOutputDeviceUID() throws -> String {
    guard let deviceID = readScalar(
        systemAudioObject,
        selector: kAudioHardwarePropertyDefaultOutputDevice,
        as: AudioObjectID.self
    ), deviceID != kAudioObjectUnknown else {
        throw ProbeFailure(
            result: "fail-no-default-output",
            stage: "read-default-output",
            message: "CoreAudio did not provide a default output device for the tap clock.",
            status: nil,
            exitCode: 4
        )
    }

    var uid: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.stride)
    var address = propertyAddress(kAudioDevicePropertyDeviceUID)
    let status = withUnsafeMutablePointer(to: &uid) { uidPointer in
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, uidPointer)
    }
    try requireSuccess(status, stage: "read-default-output-uid")
    return uid as String
}

func requireSuccess(_ status: OSStatus, stage: String) throws {
    guard status == noErr else {
        throw ProbeFailure(
            result: "fail-coreaudio-setup",
            stage: stage,
            message: "CoreAudio failed at \(stage) with \(describe(status: status)).",
            status: status,
            exitCode: 4
        )
    }
}

private func describe(status: OSStatus) -> String {
    let raw = UInt32(bitPattern: status)
    let bytes = [
        UInt8((raw >> 24) & 0xff),
        UInt8((raw >> 16) & 0xff),
        UInt8((raw >> 8) & 0xff),
        UInt8(raw & 0xff)
    ]
    if bytes.allSatisfy({ (32...126).contains($0) }) {
        return "'\(String(bytes: bytes, encoding: .ascii) ?? "????")' (\(status))"
    }
    return String(status)
}

func processAudioObjectID(for pid: pid_t) -> AudioObjectID? {
    var address = propertyAddress(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var qualifier = pid
    var objectID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafePointer(to: &qualifier) { qualifierPointer in
        AudioObjectGetPropertyData(
            systemAudioObject,
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            qualifierPointer,
            &size,
            &objectID
        )
    }
    return status == noErr && objectID != kAudioObjectUnknown ? objectID : nil
}

func processName(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 2 * (Int(MAXCOMLEN) + 1))
    let length = proc_name(pid, &buffer, UInt32(buffer.count))
    return length > 0 ? String(cString: buffer) : nil
}
