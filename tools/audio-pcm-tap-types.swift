import CoreAudio
import Foundation

struct Configuration {
    let pid: pid_t
    let seconds: Double
    let nonzeroThreshold: Float
    let minimumNonzeroSamples: UInt64
}

struct FormatReport: Codable {
    let sampleRate: Double
    let channels: UInt32
    let bitsPerChannel: UInt32
    let bytesPerFrame: UInt32
    let isFloat: Bool
    let isNonInterleaved: Bool
}

struct MeterSnapshot {
    let callbacks: UInt64
    let dataCallbacks: UInt64
    let buffers: UInt64
    let frames: UInt64
    let sampleValues: UInt64
    let finiteSamples: UInt64
    let nonzeroSamples: UInt64
    let nonfiniteSamples: UInt64
    let sumSquares: Double
    let peak: Double

    var rms: Double {
        finiteSamples == 0 ? 0 : sqrt(sumSquares / Double(finiteSamples))
    }
}

struct ProbeReport: Codable {
    let schema: String
    let generatedAtUTC: String
    let targetPID: pid_t
    let processName: String?
    let processAudioObjectID: AudioObjectID
    let durationSeconds: Double
    let permissionPreflight: String
    let capturePosition: String
    let tapMuteBehavior: String
    let endpointMuteOrVolumeAccess: String
    let rawAudioStored: Bool
    let format: FormatReport
    let callbacks: UInt64
    let dataCallbacks: UInt64
    let buffers: UInt64
    let frames: UInt64
    let sampleValues: UInt64
    let finiteSamples: UInt64
    let nonzeroSamples: UInt64
    let nonfiniteSamples: UInt64
    let nonzeroThreshold: Float
    let minimumNonzeroSamples: UInt64
    let rms: Double
    let peak: Double
    let result: String
    let interpretation: String
}

struct FailureReport: Codable {
    let schema: String
    let generatedAtUTC: String
    let targetPID: pid_t?
    let result: String
    let stage: String
    let message: String
    let osStatus: Int32?
    let permissionPromptAttempted: Bool
}

struct ProbeFailure: Error {
    let result: String
    let stage: String
    let message: String
    let status: OSStatus?
    let exitCode: Int32
}

struct WorkerResult {
    let standardOutput: Data
    let standardError: Data
    let exitCode: Int32
}

struct CleanupResult {
    let destroyedAggregates: Int
    let destroyedTaps: Int
    let failures: [String]

    var succeeded: Bool { failures.isEmpty }

    var summary: String {
        if failures.isEmpty {
            return "CoreAudio cleanup completed (aggregates: \(destroyedAggregates), taps: \(destroyedTaps))."
        }
        return "CoreAudio cleanup was incomplete: \(failures.joined(separator: "; "))."
    }
}

final class PCMMeter {
    private let threshold: Float
    private var callbacks: UInt64 = 0
    private var dataCallbacks: UInt64 = 0
    private var buffers: UInt64 = 0
    private var frames: UInt64 = 0
    private var sampleValues: UInt64 = 0
    private var finiteSamples: UInt64 = 0
    private var nonzeroSamples: UInt64 = 0
    private var nonfiniteSamples: UInt64 = 0
    private var sumSquares: Double = 0
    private var peak: Double = 0

    init(threshold: Float) {
        self.threshold = threshold
    }

    func record(_ inputData: UnsafePointer<AudioBufferList>?) {
        callbacks += 1
        guard let inputData else { return }

        let mutableList = UnsafeMutablePointer<AudioBufferList>(mutating: inputData)
        let bufferList = UnsafeMutableAudioBufferListPointer(mutableList)
        var callbackFrames = 0
        var callbackHasData = false

        for buffer in bufferList {
            buffers += 1
            guard let data = buffer.mData, buffer.mDataByteSize >= MemoryLayout<Float>.size else {
                continue
            }

            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let channelCount = max(1, Int(buffer.mNumberChannels))
            callbackFrames = max(callbackFrames, sampleCount / channelCount)
            callbackHasData = true
            record(data.assumingMemoryBound(to: Float.self), count: sampleCount)
        }

        if callbackHasData {
            dataCallbacks += 1
            frames += UInt64(callbackFrames)
        }
    }

    func recordSynthetic(_ values: [Float]) {
        values.withUnsafeBufferPointer { valuesPointer in
            guard let baseAddress = valuesPointer.baseAddress else { return }
            record(baseAddress, count: valuesPointer.count)
        }
    }

    func snapshot() -> MeterSnapshot {
        MeterSnapshot(
            callbacks: callbacks,
            dataCallbacks: dataCallbacks,
            buffers: buffers,
            frames: frames,
            sampleValues: sampleValues,
            finiteSamples: finiteSamples,
            nonzeroSamples: nonzeroSamples,
            nonfiniteSamples: nonfiniteSamples,
            sumSquares: sumSquares,
            peak: peak
        )
    }

    private func record(_ samples: UnsafePointer<Float>, count: Int) {
        sampleValues += UInt64(count)
        for index in 0..<count {
            let sample = samples[index]
            guard sample.isFinite else {
                nonfiniteSamples += 1
                continue
            }

            finiteSamples += 1
            let magnitude = abs(sample)
            if magnitude > threshold {
                nonzeroSamples += 1
            }
            let doubleSample = Double(sample)
            sumSquares += doubleSample * doubleSample
            peak = max(peak, Double(magnitude))
        }
    }
}
