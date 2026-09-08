import Foundation

@main
struct LaunchReadinessRegression {
    static var checks = 0
    static func expect(_ condition: Bool, _ name: String) throws {
        guard condition else { throw NSError(domain: name, code: 1) }
        checks += 1
        print("PASS: \(name)")
    }
    static func put(_ value: Int, at offset: Int, count: Int, in data: inout Data) {
        for index in 0..<count { data[offset + index] = UInt8((value >> (8 * index)) & 255) }
    }
    /// Synthetic PE headers and code section. Never executed; no Microsoft binary is shipped.
    static func fixture() -> Data {
        var data = Data(repeating: 0, count: 0x600)
        put(0x5a4d, at: 0, count: 2, in: &data)
        put(0x80, at: 0x3c, count: 4, in: &data)
        put(0x4550, at: 0x80, count: 4, in: &data)
        put(0x8664, at: 0x84, count: 2, in: &data)
        put(1, at: 0x86, count: 2, in: &data)
        put(240, at: 0x94, count: 2, in: &data)
        put(0x2002, at: 0x96, count: 2, in: &data)
        put(0x20b, at: 0x98, count: 2, in: &data)
        put(0x2000, at: 0x98 + 56, count: 4, in: &data)
        put(0x200, at: 0x98 + 60, count: 4, in: &data)
        put(16, at: 0x98 + 108, count: 4, in: &data)
        let section = 0x98 + 240
        put(0x1000, at: section + 8, count: 4, in: &data)
        put(0x1000, at: section + 12, count: 4, in: &data)
        put(0x400, at: section + 16, count: 4, in: &data)
        put(0x200, at: section + 20, count: 4, in: &data)
        put(0x60000020, at: section + 36, count: 4, in: &data)
        return data
    }
    static func main() async throws {
        for version in ["wine-11.0", "wine-11.0\n", "wine-11.0 (staging)\r\n"] {
            try expect(RuntimeVersionPolicy.parse(Data(version.utf8)) != nil, "version \(version.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        for invalid in ["", "\n", "warning", "wine-", "wine-bad", "wine-11.0\nwarning", "wine-11.0\nwine-11.0", "wine-11.0\u{0}"] {
            try expect(RuntimeVersionPolicy.parse(Data(invalid.utf8)) == nil, "reject invalid probe output \(invalid.debugDescription)")
        }
        try expect(RuntimeVersionPolicy.parse(Data([0xff])) == nil, "reject invalid UTF-8")
        try expect(RuntimeVersionPolicy.parse(Data(repeating: 65, count: 4097)) == nil, "bound version output")
        let valid = fixture()
        try expect(NativeAudioPayload.isValidX64DLL(valid), "accept structurally valid x64 DLL fixture")
        for invalid in [Data(), Data("not a PE file".utf8), Data("Wine placeholder DLL".utf8), Data(valid.prefix(400))] {
            try expect(!NativeAudioPayload.isValidX64DLL(invalid), "reject empty, text, placeholder or truncated fixture (\(invalid.count) bytes)")
        }
        for (offset, count, value, name) in [
            (0x84, 2, 0x14c, "x86 machine"), (0x98, 2, 0x10b, "PE32 optional header"),
            (0x3c, 4, 0xffffffff, "out-of-range PE offset"), (0x86, 2, 97, "excess sections"),
            (0x96, 2, 2, "non-DLL executable"), (0x94, 2, 0xffff, "truncated optional header"),
            (0x98 + 60, 4, 10, "invalid header size"), (0x98 + 108, 4, 17, "overflowing directories"),
            (0x98 + 240 + 20, 4, 0xffff, "out-of-file section"),
            (0x98 + 240 + 36, 4, 0x40000000, "missing executable section")
        ] {
            var corrupt = valid
            put(value, at: offset, count: count, in: &corrupt)
            try expect(!NativeAudioPayload.isValidX64DLL(corrupt), "reject \(name)")
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("secunda-readiness-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let paths = SecundaPaths(applicationSupport: root)
        try paths.prepareManagedDirectories()
        let source = paths.sourceRuntime!
        let wine = source.appendingPathComponent("bin/wine")
        try fm.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: wine)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        for path in [
            "lib/libfreetype.6.dylib", "lib/libgnutls.30.dylib", "lib/libMoltenVK.dylib",
            "lib/wine/x86_64-unix/winemetal.so", "lib/wine/x86_64-unix/winecoreaudio.so",
            "lib/wine/x86_64-windows/d3d11.dll", "lib/wine/x86_64-windows/dxgi.dll",
            "lib/wine/x86_64-windows/x3daudio1_6.dll", "lib/wine/x86_64-windows/x3daudio1_7.dll",
            "lib/wine/x86_64-windows/xaudio2_6.dll", "lib/wine/x86_64-windows/xaudio2_7.dll",
            "lib/wine/x86_64-windows/xinput1_3.dll", "lib/wine/x86_64-windows/tasklist.exe",
            "share/dxvk/x32/d3d9.dll", "share/dxvk/x64/d3d9.dll"
        ] {
            let url = source.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        let runner = ProcessRunner()
        let manager = RuntimeManager(paths: paths, processRunner: runner)
        let runtime = await manager.locate()
        try expect(runtime?.version == "wine-11.0", "real locate parses current captured stdout")
        try expect(runner.captures.last?.timeout == 5 && runner.captures.last?.limit == 4096, "real locate wires bounded capture and timeout")
        let probeLog = paths.logsDirectory.appendingPathComponent("runtime-probe.log")
        try Data("wine-99.9\n".utf8).write(to: probeLog)
        runner.output = Data()
        try expect(await manager.locate() == nil, "empty stdout cannot inherit stale log version")
        runner.output = Data("wine-11.0\n".utf8)
        runner.status = 1
        try expect(await manager.locate() == nil, "nonzero exit rejects valid-looking version")
        runner.status = 0
        runner.captureError = ProcessRunnerError.captureTimedOut(5)
        try expect(await manager.locate() == nil, "probe timeout handled without resolving runtime")
        try expect(try String(contentsOf: probeLog, encoding: .utf8).contains("probe-timeout"), "probe timeout recorded as metadata")
        runner.captureError = ProcessRunnerError.captureTooLarge(4096)
        try expect(await manager.locate() == nil, "oversized probe failure handled")
        runner.captureError = nil
        RuntimeIntegrityPolicy.inspection = .valid(source.appendingPathComponent("manifest"), Data("test".utf8))
        _ = await manager.locate()
        try expect(runner.runs.last?.timeout == 120, "integrity subprocess also has a deadline")
        RuntimeIntegrityPolicy.inspection = .absent
        let audio = VoiceAudioService(paths: paths, processRunner: runner, runtimeManager: manager)
        let system32 = paths.bottleRoot.appendingPathComponent("drive_c/windows/system32")
        try fm.createDirectory(at: system32, withIntermediateDirectories: true)
        try expect(!audio.isInstalled(bottleRoot: paths.bottleRoot), "real audio service rejects missing DLLs")
        for content in [Data(), Data("not a PE file".utf8), valid] {
            for entry in VoiceAudioService.requiredFiles { try content.write(to: system32.appendingPathComponent(entry.file)) }
            try expect(audio.isInstalled(bottleRoot: paths.bottleRoot) == (content == valid), "real audio readiness validates complete set (\(content.count) bytes)")
        }
        let broken = system32.appendingPathComponent(VoiceAudioService.requiredFiles[1].file)
        try Data().write(to: broken)
        try expect(!audio.isInstalled(bottleRoot: paths.bottleRoot), "one invalid DLL rejects whole installed set")
        // A sparse cached fixture prevents network access; the fake runner performs unpack/expand.
        let cached = paths.downloadsDirectory.appendingPathComponent("directx_Jun2010_redist.exe")
        _ = fm.createFile(atPath: cached.path, contents: nil)
        let handle = try FileHandle(forWritingTo: cached)
        try handle.truncate(atOffset: 90_000_001)
        try handle.close()
        var corruptStage = true
        runner.runBody = { arguments, directory in
            let stage = paths.bottleRoot.appendingPathComponent("drive_c/secunda-xaudio-stage")
            if arguments.first == "expand" {
                let name = arguments[2].split(separator: "\\").last.map(String.init)!
                let payload = corruptStage ? Data("invalid".utf8) : valid
                try payload.write(to: stage.appendingPathComponent("payload/\(name)"))
            } else {
                for entry in VoiceAudioService.requiredFiles { try Data().write(to: stage.appendingPathComponent(entry.cabinet)) }
            }
            return 0
        }
        let before = try VoiceAudioService.requiredFiles.map { try Data(contentsOf: system32.appendingPathComponent($0.file)) }
        do {
            try await audio.installIfNeeded(runtime: runtime!, diagnostics: false)
            try expect(false, "corrupt staged set must fail")
        } catch VoiceAudioError.installIncomplete {
            let after = try VoiceAudioService.requiredFiles.map { try Data(contentsOf: system32.appendingPathComponent($0.file)) }
            try expect(before == after, "bad staged payload leaves every live DLL unchanged")
        }
        corruptStage = false
        try await audio.installIfNeeded(runtime: runtime!, diagnostics: false)
        try expect(audio.isInstalled(bottleRoot: paths.bottleRoot), "validated staged set repairs invalid install")
        try expect(runner.runs.filter { $0.arguments.first == "expand" }.allSatisfy { $0.arguments[2].contains("\\payload\\") }, "all expansion targets remain in staging")
        let count = runner.runs.count
        try await audio.installIfNeeded(runtime: runtime!, diagnostics: false)
        try expect(runner.runs.count == count, "valid installed set avoids reinstall")
        let link = root.appendingPathComponent("linked.dll")
        try fm.createSymbolicLink(at: link, withDestinationURL: system32.appendingPathComponent(VoiceAudioService.requiredFiles[0].file))
        try expect(NativeAudioPayload.validatedContents(at: link) == nil, "symlink is not treated as installed native payload")
        // Exercise rotation and bounded metadata without storing any raw runtime output.
        for _ in 0..<600 { RuntimeProbeLog.record(at: probeLog, origin: "test", candidateID: "test", outcome: "ready", version: "wine-11.0") }
        let logData = try Data(contentsOf: probeLog)
        try expect(logData.count <= 65_536, "probe metadata stays bounded")
        try expect(String(data: logData, encoding: .utf8)?.contains(root.path) == false, "probe metadata omits personal paths")
        print("\(checks) launch-readiness regression checks passed. No Wine/game execution performed.")
    }
}
