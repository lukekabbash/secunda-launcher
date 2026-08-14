import CoreGraphics
import Foundation
import ScreenCaptureKit

enum GameFrameState: String, Codable, Equatable, Sendable {
    case allBlack
    case nonBlackStatic
    case nonBlackChanging
    case capturePermissionUnavailable
    case windowUnavailable
    case unreadableFrame
    case captureFailed
}

/// Numeric-only result from two bounded window captures. No image data is
/// retained or written to the diagnostic record.
struct GameFrameObservation: Codable, Equatable, Sendable {
    let state: GameFrameState
    let captureWidth: Int?
    let captureHeight: Int?
    let sampleCount: Int
    let firstNonBlackPermille: Int?
    let secondNonBlackPermille: Int?
    let changedPermille: Int?

    static func unavailable(_ state: GameFrameState) -> GameFrameObservation {
        GameFrameObservation(
            state: state,
            captureWidth: nil,
            captureHeight: nil,
            sampleCount: 0,
            firstNonBlackPermille: nil,
            secondNonBlackPermille: nil,
            changedPermille: nil
        )
    }
}

/// Samples one visible window twice. The probe deliberately
/// avoids requesting screen-capture permission or persisting image pixels.
final class MacGameFrameProbe {
    private static let captureWidthLimit = 320
    private static let captureHeightLimit = 180
    private static let sampleColumns = 64
    private static let sampleRows = 36
    private static let nonBlackLumaThreshold = 8
    private static let changedLumaThreshold = 8

    private enum CaptureError: Error {
        case unreadableFrame
    }

    private struct FrameSample {
        let width: Int
        let height: Int
        let lumas: [UInt8]
        let nonBlackPermille: Int
    }

    func observe(surface: GameWindowSurface) async -> GameFrameObservation {
        guard surface.isVisible, surface.windowID != 0 else {
            return .unavailable(.windowUnavailable)
        }
        guard CGPreflightScreenCaptureAccess() else {
            return .unavailable(.capturePermissionUnavailable)
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let window = content.windows.first(where: {
                $0.windowID == surface.windowID
            }) else {
                return .unavailable(.windowUnavailable)
            }

            let first = try await Self.capture(window: window, surface: surface)
            try await Task.sleep(for: .milliseconds(650))
            let second = try await Self.capture(window: window, surface: surface)
            let changedPermille = Self.changedPermille(first.lumas, second.lumas)
            return GameFrameObservation(
                state: Self.classify(
                    firstNonBlackPermille: first.nonBlackPermille,
                    secondNonBlackPermille: second.nonBlackPermille,
                    changedPermille: changedPermille
                ),
                captureWidth: first.width,
                captureHeight: first.height,
                sampleCount: first.lumas.count,
                firstNonBlackPermille: first.nonBlackPermille,
                secondNonBlackPermille: second.nonBlackPermille,
                changedPermille: changedPermille
            )
        } catch CaptureError.unreadableFrame {
            return .unavailable(.unreadableFrame)
        } catch {
            return .unavailable(.captureFailed)
        }
    }

    static func classify(
        firstNonBlackPermille: Int,
        secondNonBlackPermille: Int,
        changedPermille: Int?
    ) -> GameFrameState {
        guard max(firstNonBlackPermille, secondNonBlackPermille) > 0 else {
            return .allBlack
        }
        return (changedPermille ?? 0) > 0 ? .nonBlackChanging : .nonBlackStatic
    }

    private static func capture(
        window: SCWindow,
        surface: GameWindowSurface
    ) async throws -> FrameSample {
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, min(surface.width, captureWidthLimit))
        configuration.height = max(1, min(surface.height, captureHeightLimit))
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return try sample(image)
    }

    private static func sample(_ image: CGImage) throws -> FrameSample {
        guard image.width > 0,
              image.height > 0,
              image.bitsPerComponent == 8,
              image.bitsPerPixel >= 24,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else {
            throw CaptureError.unreadableFrame
        }

        let bytesPerPixel = image.bitsPerPixel / 8
        let requiredBytes = image.bytesPerRow * image.height
        guard bytesPerPixel >= 3, CFDataGetLength(data) >= requiredBytes else {
            throw CaptureError.unreadableFrame
        }

        let columns = min(sampleColumns, image.width)
        let rows = min(sampleRows, image.height)
        var lumas: [UInt8] = []
        lumas.reserveCapacity(columns * rows)
        var nonBlackCount = 0

        for row in 0..<rows {
            let y = min(image.height - 1, ((row * 2 + 1) * image.height) / (rows * 2))
            for column in 0..<columns {
                let x = min(image.width - 1, ((column * 2 + 1) * image.width) / (columns * 2))
                let offset = y * image.bytesPerRow + x * bytesPerPixel
                let luma = UInt8(
                    (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
                )
                lumas.append(luma)
                if luma >= nonBlackLumaThreshold {
                    nonBlackCount += 1
                }
            }
        }

        guard !lumas.isEmpty else { throw CaptureError.unreadableFrame }
        return FrameSample(
            width: image.width,
            height: image.height,
            lumas: lumas,
            nonBlackPermille: nonBlackCount * 1_000 / lumas.count
        )
    }

    private static func changedPermille(_ first: [UInt8], _ second: [UInt8]) -> Int? {
        guard first.count == second.count, !first.isEmpty else { return nil }
        let changed = zip(first, second).reduce(into: 0) { count, pair in
            if abs(Int(pair.0) - Int(pair.1)) >= changedLumaThreshold {
                count += 1
            }
        }
        return changed * 1_000 / first.count
    }
}
