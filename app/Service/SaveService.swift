import Foundation

final class SaveService {
    private let paths: SecundaPaths

    init(paths: SecundaPaths) {
        self.paths = paths
    }

    func saveDirectory(in bottleRoot: URL) -> URL? {
        let users = bottleRoot.appendingPathComponent("drive_c/users", isDirectory: true)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: users,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return children
            .filter { !["Public", "All Users", "Default User"].contains($0.lastPathComponent) }
            .map { $0.appendingPathComponent("Documents/My Games/Skyrim Special Edition/Saves") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func saveCount(in bottleRoot: URL) -> Int {
        guard let saveDirectory = saveDirectory(in: bottleRoot),
              let files = try? FileManager.default.contentsOfDirectory(atPath: saveDirectory.path)
        else { return 0 }
        return files.filter { $0.lowercased().hasSuffix(".ess") }.count
    }

    var backupCount: Int {
        (try? FileManager.default.contentsOfDirectory(
            at: paths.backupsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).count) ?? 0
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
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
            .appendingPathComponent("Saves", isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: saveDirectory, to: destination)
        return destination
    }
}
