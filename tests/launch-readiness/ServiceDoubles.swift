import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Unit-test boundaries only. The script compiles the real RuntimeManager and
// VoiceAudioService against these doubles; no Wine, network or user prefix is used.
struct SecundaPaths {
    let applicationSupport: URL
    var repositoryRoot: URL? { applicationSupport }
    var sourceRuntime: URL? { applicationSupport.appendingPathComponent("Runtime/wine") }
    var bottleRoot: URL { applicationSupport.appendingPathComponent("bottle") }
    var logsDirectory: URL { applicationSupport.appendingPathComponent("logs") }
    var downloadsDirectory: URL { applicationSupport.appendingPathComponent("downloads") }
    var graphicsCacheDirectory: URL { applicationSupport.appendingPathComponent("cache") }
    func isManagedBottleRoot(_ url: URL) -> Bool { url == bottleRoot }
    func prepareManagedDirectories() throws {
        for url in [bottleRoot, logsDirectory, downloadsDirectory] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
enum SourceRuntimePolicy {
    static func allows(executable: URL, trustedRuntimeRoot: URL?) -> Bool { true }
}
enum RuntimeIntegrityPolicy {
    enum Inspection { case absent, invalid, valid(URL, Data) }
    static var inspection: Inspection = .absent
    static func inspect(runtimeRoot: URL) -> Inspection { inspection }
    static func validatesEntries(_ data: Data, runtimeRoot: URL) -> Bool { true }
}
enum ProcessRunnerError: Error {
    case captureTimedOut(TimeInterval)
    case captureTooLarge(Int)
    case launchFailed
}
struct CapturedProcessResult { let terminationStatus: Int32; let output: Data }
struct ProcessResult { let terminationStatus: Int32; let logURL: URL }
final class ProcessRunner {
    var output = Data("wine-11.0\n".utf8)
    var status: Int32 = 0
    var captureError: Error?
    var captures: [(limit: Int, timeout: TimeInterval)] = []
    var runs: [(arguments: [String], timeout: TimeInterval?)] = []
    var runBody: (([String], URL?) throws -> Int32)?
    func capture(
        executable: URL, arguments: [String], environment: [String: String],
        maxOutputBytes: Int, timeoutSeconds: TimeInterval
    ) async throws -> CapturedProcessResult {
        captures.append((maxOutputBytes, timeoutSeconds))
        if let captureError { throw captureError }
        return CapturedProcessResult(terminationStatus: status, output: output)
    }
    func run(
        executable: URL, arguments: [String], environment: [String: String],
        currentDirectory: URL? = nil, logURL: URL, timeoutSeconds: TimeInterval? = nil
    ) async throws -> ProcessResult {
        runs.append((arguments, timeoutSeconds))
        let code = try runBody?(arguments, currentDirectory) ?? 0
        return ProcessResult(terminationStatus: code, logURL: logURL)
    }
}
