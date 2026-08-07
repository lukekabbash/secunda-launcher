import CoreAudio
import Darwin
import Foundation

struct AudioLevelDelta {
    var scalarSamples = 0
    var nonSilentSamples = 0
    var clippedSamples = 0
    var invalidSamples = 0
    var sumSquares = 0.0
    var peakMagnitude = 0.0

    mutating func observe(_ sample: Double, thresholdLinear: Double) {
        guard sample.isFinite else {
            invalidSamples += 1
            return
        }

        let magnitude = abs(sample)
        scalarSamples += 1
        sumSquares += sample * sample
        peakMagnitude = max(peakMagnitude, magnitude)
        if magnitude >= thresholdLinear {
            nonSilentSamples += 1
        }
        if magnitude >= 0.999 {
            clippedSamples += 1
        }
    }
}

struct PCMFormatIdentity: Equatable {
    enum Encoding: String {
        case float32
        case float64
        case signedInt16
        case signedInt32
    }

    let sampleRateHz: Int
    let channelCount: Int
    let encoding: Encoding
    let bytesPerSample: Int

    init?(streamDescription: AudioStreamBasicDescription) {
        guard streamDescription.mFormatID == kAudioFormatLinearPCM,
              streamDescription.mSampleRate.isFinite,
              streamDescription.mSampleRate > 0,
              streamDescription.mChannelsPerFrame > 0,
              streamDescription.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              streamDescription.mFormatFlags & kAudioFormatFlagIsPacked != 0 else {
            return nil
        }

        let isFloat = streamDescription.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = streamDescription.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        switch (isFloat, isSignedInteger, streamDescription.mBitsPerChannel) {
        case (true, false, 32):
            encoding = .float32
            bytesPerSample = MemoryLayout<Float>.size
        case (true, false, 64):
            encoding = .float64
            bytesPerSample = MemoryLayout<Double>.size
        case (false, true, 16):
            encoding = .signedInt16
            bytesPerSample = MemoryLayout<Int16>.size
        case (false, true, 32):
            encoding = .signedInt32
            bytesPerSample = MemoryLayout<Int32>.size
        default:
            return nil
        }

        sampleRateHz = Int(streamDescription.mSampleRate.rounded())
        channelCount = Int(streamDescription.mChannelsPerFrame)
    }
}

enum PCMLevelDecoder {
    static func summarize(
        _ buffers: UnsafeMutableAudioBufferListPointer,
        format: PCMFormatIdentity,
        thresholdLinear: Double
    ) -> AudioLevelDelta {
        var result = AudioLevelDelta()
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let byteCount = Int(buffer.mDataByteSize)
            let sampleCount = byteCount / format.bytesPerSample
            let raw = UnsafeRawPointer(data)

            for index in 0..<sampleCount {
                let offset = index * format.bytesPerSample
                let value = normalizedSample(
                    at: raw.advanced(by: offset),
                    encoding: format.encoding
                )
                result.observe(value, thresholdLinear: thresholdLinear)
            }
        }
        return result
    }

    private static func normalizedSample(
        at pointer: UnsafeRawPointer,
        encoding: PCMFormatIdentity.Encoding
    ) -> Double {
        switch encoding {
        case .float32:
            var value: Float = 0
            memcpy(&value, pointer, MemoryLayout<Float>.size)
            return Double(value)
        case .float64:
            var value = 0.0
            memcpy(&value, pointer, MemoryLayout<Double>.size)
            return value
        case .signedInt16:
            var value: Int16 = 0
            memcpy(&value, pointer, MemoryLayout<Int16>.size)
            return Double(value) / 32_768.0
        case .signedInt32:
            var value: Int32 = 0
            memcpy(&value, pointer, MemoryLayout<Int32>.size)
            return Double(value) / 2_147_483_648.0
        }
    }
}

struct AudioLevelSnapshot {
    let format: PCMFormatIdentity?
    let audioBufferCount: Int
    let audioFrameCount: Int
    let scalarSampleCount: Int
    let nonSilentBufferCount: Int
    let nonSilentSampleCount: Int
    let clippedSampleCount: Int
    let invalidSampleCount: Int
    let malformedBufferCount: Int
    let formatChangeCount: Int
    let sumSquares: Double
    let peakMagnitude: Double

    var pcmDurationSeconds: Double {
        guard let format, format.sampleRateHz > 0 else { return 0 }
        return Double(audioFrameCount) / Double(format.sampleRateHz)
    }

    var rmsMagnitude: Double {
        guard scalarSampleCount > 0 else { return 0 }
        return sqrt(sumSquares / Double(scalarSampleCount))
    }
}

struct AudioLevelAccumulator {
    private(set) var format: PCMFormatIdentity?
    private(set) var audioBufferCount = 0
    private(set) var audioFrameCount = 0
    private(set) var scalarSampleCount = 0
    private(set) var nonSilentBufferCount = 0
    private(set) var nonSilentSampleCount = 0
    private(set) var clippedSampleCount = 0
    private(set) var invalidSampleCount = 0
    private(set) var malformedBufferCount = 0
    private(set) var formatChangeCount = 0
    private(set) var sumSquares = 0.0
    private(set) var peakMagnitude = 0.0

    mutating func record(
        _ delta: AudioLevelDelta,
        frameCount: Int,
        format observedFormat: PCMFormatIdentity
    ) {
        if let format, format != observedFormat {
            formatChangeCount += 1
        } else if format == nil {
            format = observedFormat
        }

        let expectedSamples = max(0, frameCount) * observedFormat.channelCount
        if frameCount <= 0 || delta.scalarSamples != expectedSamples {
            malformedBufferCount += 1
        }

        audioBufferCount += 1
        audioFrameCount += max(0, frameCount)
        scalarSampleCount += delta.scalarSamples
        nonSilentSampleCount += delta.nonSilentSamples
        clippedSampleCount += delta.clippedSamples
        invalidSampleCount += delta.invalidSamples
        sumSquares += delta.sumSquares
        peakMagnitude = max(peakMagnitude, delta.peakMagnitude)
        if delta.nonSilentSamples > 0 {
            nonSilentBufferCount += 1
        }
    }

    mutating func recordMalformedBuffer() {
        malformedBufferCount += 1
    }

    func snapshot() -> AudioLevelSnapshot {
        AudioLevelSnapshot(
            format: format,
            audioBufferCount: audioBufferCount,
            audioFrameCount: audioFrameCount,
            scalarSampleCount: scalarSampleCount,
            nonSilentBufferCount: nonSilentBufferCount,
            nonSilentSampleCount: nonSilentSampleCount,
            clippedSampleCount: clippedSampleCount,
            invalidSampleCount: invalidSampleCount,
            malformedBufferCount: malformedBufferCount,
            formatChangeCount: formatChangeCount,
            sumSquares: sumSquares,
            peakMagnitude: peakMagnitude
        )
    }
}

func levelDBFS(_ magnitude: Double) -> String {
    guard magnitude.isFinite, magnitude > 0 else { return "NEG_INF" }
    return fixedAudioMetric(20 * log10(magnitude))
}

func fixedAudioMetric(_ value: Double) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
}
