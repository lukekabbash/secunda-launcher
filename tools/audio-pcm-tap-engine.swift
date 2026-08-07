import AudioToolbox
import CoreAudio
import Foundation

private final class AUHALCaptureContext {
    private let meter: PCMMeter
    private let maximumFrames: UInt32
    private let bytesPerFrame: UInt32
    private let bufferList: UnsafeMutablePointer<AudioBufferList>
    private let sampleStorage: UnsafeMutableRawPointer
    var audioUnit: AudioUnit?

    init(meter: PCMMeter, channels: UInt32, maximumFrames: UInt32) {
        self.meter = meter
        self.maximumFrames = maximumFrames
        bytesPerFrame = channels * UInt32(MemoryLayout<Float>.size)

        let byteCount = Int(maximumFrames * bytesPerFrame)
        sampleStorage = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<Float>.alignment
        )
        bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        bufferList.initialize(to: AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: channels,
                mDataByteSize: UInt32(byteCount),
                mData: sampleStorage
            )
        ))
    }

    deinit {
        bufferList.deinitialize(count: 1)
        bufferList.deallocate()
        sampleStorage.deallocate()
    }

    func render(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frames: UInt32
    ) -> OSStatus {
        guard let audioUnit, frames <= maximumFrames else {
            return kAudio_ParamError
        }

        bufferList.pointee.mBuffers.mDataByteSize = frames * bytesPerFrame
        let status = AudioUnitRender(
            audioUnit,
            actionFlags,
            timestamp,
            1,
            frames,
            bufferList
        )
        if status == noErr {
            meter.record(UnsafePointer(bufferList))
        }
        return status
    }
}

final class TapSession {
    private let runToken: String
    private(set) var tapID = AudioObjectID(kAudioObjectUnknown)
    private(set) var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var audioUnit: AudioUnit?
    private var captureContext: AUHALCaptureContext?
    private var isInitialized = false
    private(set) var isRunning = false

    init(runToken: String) {
        self.runToken = runToken
    }

    deinit {
        close()
    }

    func close() {
        if isRunning, let audioUnit {
            _ = AudioOutputUnitStop(audioUnit)
            isRunning = false
        }
        if isInitialized, let audioUnit {
            _ = AudioUnitUninitialize(audioUnit)
            isInitialized = false
        }
        if let audioUnit {
            _ = AudioComponentInstanceDispose(audioUnit)
            self.audioUnit = nil
        }
        captureContext = nil
        if aggregateDeviceID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    func createTap(for processAudioObjectID: AudioObjectID) throws -> AudioStreamBasicDescription {
        let identity = probeObjectIdentity(runToken: runToken)
        let description = CATapDescription()
        description.name = identity.tapName
        description.uuid = UUID(uuidString: identity.tapUID)!
        description.processes = [processAudioObjectID]
        description.isPrivate = false
        description.isExclusive = false
        description.isMixdown = true
        description.isMono = false
        description.muteBehavior = .unmuted

        let createStatus = AudioHardwareCreateProcessTap(description, &tapID)
        try requireSuccess(createStatus, stage: "create-process-tap")
        guard tapID != kAudioObjectUnknown else {
            throw ProbeFailure(
                result: "fail-tap-creation",
                stage: "create-process-tap",
                message: "CoreAudio returned an unknown tap object.",
                status: nil,
                exitCode: 4
            )
        }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = propertyAddress(kAudioTapPropertyFormat)
        let formatStatus = AudioObjectGetPropertyData(
            tapID,
            &formatAddress,
            0,
            nil,
            &size,
            &format
        )
        try requireSuccess(formatStatus, stage: "read-tap-format")
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else {
            throw ProbeFailure(
                result: "fail-unsupported-pcm-format",
                stage: "read-tap-format",
                message: "The process tap did not expose 32-bit floating-point linear PCM.",
                status: nil,
                exitCode: 4
            )
        }
        return format
    }

    func createAggregateDevice() throws {
        let identity = probeObjectIdentity(runToken: runToken)
        let outputDeviceUID = try defaultOutputDeviceUID()
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: identity.aggregateName,
            kAudioAggregateDeviceUIDKey: identity.aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID
        ]
        let createStatus = AudioHardwareCreateAggregateDevice(
            description as CFDictionary,
            &aggregateDeviceID
        )
        try requireSuccess(createStatus, stage: "create-aggregate-device")
        guard aggregateDeviceID != kAudioObjectUnknown else {
            throw ProbeFailure(
                result: "fail-aggregate-creation",
                stage: "create-aggregate-device",
                message: "CoreAudio returned an unknown aggregate device.",
                status: nil,
                exitCode: 4
            )
        }
        let tapUID = try readTapUID()
        try addTap(uid: tapUID)
        try waitForInputStream()
    }

    func configureCapture(tapFormat: AudioStreamBasicDescription, meter: PCMMeter) throws {
        var componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &componentDescription) else {
            throw ProbeFailure(
                result: "fail-auhal-component",
                stage: "find-auhal-component",
                message: "CoreAudio did not provide the system AUHAL component.",
                status: nil,
                exitCode: 4
            )
        }

        var createdUnit: AudioUnit?
        try requireSuccess(
            AudioComponentInstanceNew(component, &createdUnit),
            stage: "create-auhal-instance"
        )
        guard let createdUnit else {
            throw ProbeFailure(
                result: "fail-auhal-component",
                stage: "create-auhal-instance",
                message: "CoreAudio did not return an AUHAL instance.",
                status: nil,
                exitCode: 4
            )
        }
        audioUnit = createdUnit

        var enableInput: UInt32 = 1
        try requireSuccess(
            AudioUnitSetProperty(
                createdUnit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input,
                1,
                &enableInput,
                UInt32(MemoryLayout<UInt32>.size)
            ),
            stage: "enable-auhal-input"
        )

        var disableOutput: UInt32 = 0
        try requireSuccess(
            AudioUnitSetProperty(
                createdUnit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output,
                0,
                &disableOutput,
                UInt32(MemoryLayout<UInt32>.size)
            ),
            stage: "disable-auhal-output"
        )

        var deviceID = aggregateDeviceID
        try requireSuccess(
            AudioUnitSetProperty(
                createdUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioObjectID>.size)
            ),
            stage: "select-aggregate-device"
        )

        var clientFormat = interleavedFloatFormat(matching: tapFormat)
        try requireSuccess(
            AudioUnitSetProperty(
                createdUnit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                1,
                &clientFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            ),
            stage: "set-auhal-client-format"
        )

        var maximumFrames: UInt32 = 16_384
        try requireSuccess(
            AudioUnitSetProperty(
                createdUnit,
                kAudioUnitProperty_MaximumFramesPerSlice,
                kAudioUnitScope_Global,
                0,
                &maximumFrames,
                UInt32(MemoryLayout<UInt32>.size)
            ),
            stage: "set-auhal-maximum-frames"
        )

        let context = AUHALCaptureContext(
            meter: meter,
            channels: clientFormat.mChannelsPerFrame,
            maximumFrames: maximumFrames
        )
        context.audioUnit = createdUnit
        captureContext = context
        var callback = AURenderCallbackStruct(
            inputProc: audioUnitInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(context).toOpaque()
        )
        try requireSuccess(
            AudioUnitSetProperty(
                createdUnit,
                kAudioOutputUnitProperty_SetInputCallback,
                kAudioUnitScope_Global,
                0,
                &callback,
                UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            ),
            stage: "set-auhal-input-callback"
        )

        try requireSuccess(AudioUnitInitialize(createdUnit), stage: "initialize-auhal")
        isInitialized = true
    }

    func start() throws {
        guard let audioUnit else {
            throw ProbeFailure(
                result: "fail-auhal-state",
                stage: "start-auhal",
                message: "The AUHAL capture unit was not configured.",
                status: nil,
                exitCode: 4
            )
        }
        let status = AudioOutputUnitStart(audioUnit)
        try requireSuccess(status, stage: "start-auhal")
        isRunning = true
    }

    func stop() throws {
        guard isRunning else { return }
        guard let audioUnit else { return }
        let status = AudioOutputUnitStop(audioUnit)
        isRunning = false
        try requireSuccess(status, stage: "stop-auhal")
    }

    private func readTapUID() throws -> CFString {
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.stride)
        var address = propertyAddress(kAudioTapPropertyUID)
        let status = withUnsafeMutablePointer(to: &uid) { uidPointer in
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, uidPointer)
        }
        try requireSuccess(status, stage: "read-tap-uid")
        return uid
    }

    private func addTap(uid: CFString) throws {
        var address = propertyAddress(kAudioAggregateDevicePropertyTapList)
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            aggregateDeviceID,
            &address,
            0,
            nil,
            &size
        )
        try requireSuccess(sizeStatus, stage: "read-aggregate-tap-list-size")

        var currentList: CFArray? = nil
        let readStatus = withUnsafeMutablePointer(to: &currentList) { listPointer in
            AudioObjectGetPropertyData(
                aggregateDeviceID,
                &address,
                0,
                nil,
                &size,
                listPointer
            )
        }
        try requireSuccess(readStatus, stage: "read-aggregate-tap-list")

        var tapUIDs = currentList as? [CFString] ?? []
        if !tapUIDs.contains(uid) {
            tapUIDs.append(uid)
        }
        currentList = tapUIDs as CFArray
        let objectReferenceSize = UInt32(MemoryLayout<CFArray?>.size)
        let writeStatus = withUnsafePointer(to: &currentList) { listPointer in
            AudioObjectSetPropertyData(
                aggregateDeviceID,
                &address,
                0,
                nil,
                objectReferenceSize,
                listPointer
            )
        }
        try requireSuccess(writeStatus, stage: "write-aggregate-tap-list")
    }

    private func waitForInputStream() throws {
        let deadline = Date().addingTimeInterval(2)
        repeat {
            let streamIDs = readArray(
                aggregateDeviceID,
                selector: kAudioDevicePropertyStreams,
                as: AudioObjectID.self
            )
            if streamIDs.contains(where: { streamID in
                readScalar(
                    streamID,
                    selector: kAudioStreamPropertyDirection,
                    as: UInt32.self
                ) == 1
            }) {
                return
            }
            Thread.sleep(forTimeInterval: 0.025)
        } while Date() < deadline

        throw ProbeFailure(
            result: "fail-aggregate-not-ready",
            stage: "wait-for-input-stream",
            message: "The aggregate device did not publish the process tap as an input stream.",
            status: nil,
            exitCode: 4
        )
    }
}

private func audioUnitInputCallback(
    _ contextPointer: UnsafeMutableRawPointer,
    _ actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    _ timestamp: UnsafePointer<AudioTimeStamp>,
    _ busNumber: UInt32,
    _ frameCount: UInt32,
    _ data: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let context = Unmanaged<AUHALCaptureContext>
        .fromOpaque(contextPointer)
        .takeUnretainedValue()
    return context.render(
        actionFlags: actionFlags,
        timestamp: timestamp,
        frames: frameCount
    )
}

private func interleavedFloatFormat(
    matching source: AudioStreamBasicDescription
) -> AudioStreamBasicDescription {
    let bytesPerFrame = source.mChannelsPerFrame * UInt32(MemoryLayout<Float>.size)
    return AudioStreamBasicDescription(
        mSampleRate: source.mSampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: bytesPerFrame,
        mFramesPerPacket: 1,
        mBytesPerFrame: bytesPerFrame,
        mChannelsPerFrame: source.mChannelsPerFrame,
        mBitsPerChannel: 32,
        mReserved: 0
    )
}
