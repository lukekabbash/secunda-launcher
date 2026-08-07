import AppKit
import CoreGraphics
import Darwin
import Foundation
import ScreenCaptureKit

private struct Options {
    let processID: pid_t
    let windowID: CGWindowID
    let outputPath: String
}

private final class HardWatchdog: @unchecked Sendable {
    private let timer: DispatchSourceTimer

    init(timeoutSeconds: Double) {
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + timeoutSeconds)
        timer.setEventHandler { _exit(124) }
        timer.resume()
    }

    func cancel() {
        timer.setEventHandler {}
        timer.cancel()
    }
}

private func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("Window snapshot failed: \(message)\n".utf8))
    exit(code)
}

private func parseOptions(_ arguments: ArraySlice<String>) -> Options {
    var iterator = arguments.makeIterator()
    var processID: pid_t?
    var windowID: CGWindowID?
    var outputPath: String?

    while let argument = iterator.next() {
        guard let value = iterator.next() else { fail("missing argument value") }
        switch argument {
        case "--pid": processID = pid_t(value)
        case "--window-id": windowID = CGWindowID(value)
        case "--output": outputPath = value
        default: fail("unknown argument")
        }
    }

    guard let processID, processID > 0,
          let windowID, windowID > 0,
          let outputPath, !outputPath.isEmpty else {
        fail("usage: window-snapshot --pid PID --window-id ID --output PNG")
    }
    return Options(processID: processID, windowID: windowID, outputPath: outputPath)
}

@main
private struct WindowSnapshot {
    static func main() async {
        let options = parseOptions(CommandLine.arguments.dropFirst())
        let watchdog = HardWatchdog(timeoutSeconds: 20)
        defer { watchdog.cancel() }

        guard kill(options.processID, 0) == 0 || errno == EPERM else {
            fail("target process is not running", code: 66)
        }
        guard CGPreflightScreenCaptureAccess() else {
            fail("Screen Recording permission is not already granted; no access request was made", code: 77)
        }
        _ = NSApplication.shared.setActivationPolicy(.prohibited)

        do {
            let content = try await SCShareableContent.current
            guard let window = content.windows.first(where: {
                $0.windowID == options.windowID
                    && $0.owningApplication?.processID == options.processID
                    && $0.isOnScreen
            }) else {
                fail("exact onscreen window does not belong to the requested PID", code: 66)
            }

            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(window.frame.width))
            configuration.height = max(1, Int(window.frame.height))
            configuration.showsCursor = false
            configuration.capturesAudio = false

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let representation = NSBitmapImageRep(cgImage: image)
            guard let png = representation.representation(using: .png, properties: [:]) else {
                fail("could not encode exact-window PNG", code: 69)
            }
            try png.write(to: URL(fileURLWithPath: options.outputPath), options: .atomic)
            print("SNAPSHOT_RESULT=PASS")
        } catch {
            fail("ScreenCaptureKit exact-window capture failed", code: 69)
        }
    }
}
