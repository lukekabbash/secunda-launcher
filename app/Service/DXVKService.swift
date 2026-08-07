import Foundation

enum DXVKError: LocalizedError {
    case runtimePayloadMissing
    case installIncomplete

    var errorDescription: String? {
        switch self {
        case .runtimePayloadMissing:
            "This Secunda build is missing its DXVK graphics components. Reinstall the complete Secunda package."
        case .installIncomplete:
            "The DXVK graphics components did not install completely."
        }
    }
}

/// Installs DXVK's Direct3D 9 implementation (D3D9 → Vulkan → Metal via
/// MoltenVK) into the managed game space for games that opt into it. The
/// DLLs ship inside Secunda's runtime under share/dxvk and are copied per
/// prefix; the per-launch d3d9 override decides whether a game uses them,
/// so wined3d-path games are untouched even after installation.
final class DXVKService {
    /// Files copied into the prefix: (runtime source subpath, prefix destination).
    static let payload: [(source: String, destination: String)] = [
        (source: "share/dxvk/x64/d3d9.dll", destination: "drive_c/windows/system32/d3d9.dll"),
        (source: "share/dxvk/x32/d3d9.dll", destination: "drive_c/windows/syswow64/d3d9.dll")
    ]

    private let paths: SecundaPaths

    init(paths: SecundaPaths) {
        self.paths = paths
    }

    /// A DXVK build of d3d9.dll carries its own marker strings; Wine's
    /// builtin does not. Presence of the file alone proves nothing.
    static func isDXVKBinary(_ data: Data) -> Bool {
        data.range(of: Data("dxvk".utf8)) != nil || data.range(of: Data("DXVK".utf8)) != nil
    }

    func isInstalled(bottleRoot: URL) -> Bool {
        Self.payload.allSatisfy { entry in
            let url = bottleRoot.appendingPathComponent(entry.destination)
            guard let data = try? Data(contentsOf: url) else { return false }
            return Self.isDXVKBinary(data)
        }
    }

    func installIfNeeded(runtime: RuntimeDescriptor, diagnostics: Bool) throws {
        guard !isInstalled(bottleRoot: runtime.bottleRoot) else { return }
        guard paths.isManagedBottleRoot(runtime.bottleRoot) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let runtimeRoot = runtime.wineExecutable
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let manager = FileManager.default
        for entry in Self.payload {
            let source = runtimeRoot.appendingPathComponent(entry.source)
            guard manager.fileExists(atPath: source.path) else {
                throw DXVKError.runtimePayloadMissing
            }
            let destination = runtime.bottleRoot.appendingPathComponent(entry.destination)
            guard paths.contains(destination, inBottleRoot: runtime.bottleRoot) else {
                throw CocoaError(.fileWriteNoPermission)
            }
            try manager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.copyItem(at: source, to: destination)
        }

        guard isInstalled(bottleRoot: runtime.bottleRoot) else {
            throw DXVKError.installIncomplete
        }
    }
}
