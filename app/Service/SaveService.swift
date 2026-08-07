import Foundation

final class SaveService {
    private let paths: SecundaPaths
    private let descriptor: GameDescriptor

    init(paths: SecundaPaths, descriptor: GameDescriptor) {
        self.paths = paths
        self.descriptor = descriptor
    }

    func saveDirectory(in bottleRoot: URL) -> URL? {
        guard BottleManager.hasPrivateDocuments(paths: paths, bottleRoot: bottleRoot) else {
            return nil
        }
        let saves = paths.activeWindowsUserDirectory(in: bottleRoot)
            .appendingPathComponent(
                "Documents/\(descriptor.documentsRelativePath)/Saves",
                isDirectory: true
            )
        return paths.contains(saves, inBottleRoot: bottleRoot)
            && FileManager.default.fileExists(atPath: saves.path) ? saves : nil
    }

    func saveCount(in bottleRoot: URL) -> Int {
        guard let saveDirectory = saveDirectory(in: bottleRoot),
              let files = try? FileManager.default.contentsOfDirectory(atPath: saveDirectory.path)
        else { return 0 }
        let extensions = descriptor.saveFileExtensions.map { "." + $0 }
        return files.filter { file in
            let lowered = file.lowercased()
            return extensions.contains { lowered.hasSuffix($0) }
        }.count
    }

    var backupCount: Int {
        (try? FileManager.default.contentsOfDirectory(
            at: paths.backupsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent.hasPrefix(backupPrefix) }.count) ?? 0
    }

    @discardableResult
    func createBackup(in bottleRoot: URL) throws -> URL {
        guard let saveDirectory = saveDirectory(in: bottleRoot) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try paths.prepareManagedDirectories()

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let destination = paths.backupsDirectory
            .appendingPathComponent(
                backupPrefix + formatter.string(from: Date()),
                isDirectory: true
            )
            .appendingPathComponent("Saves", isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: saveDirectory, to: destination)
        return destination
    }

    /// Legacy Skyrim backups predate per-game prefixes; keep counting them.
    private var backupPrefix: String {
        descriptor.id == GameDescriptor.skyrimSE.id ? "" : descriptor.id + "-"
    }
}
