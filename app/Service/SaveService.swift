import Foundation

final class SaveService {
    private let paths: SecundaPaths

    init(paths: SecundaPaths) {
        self.paths = paths
    }

    func saveDirectory(in bottleRoot: URL) -> URL? {
        guard BottleManager.hasPrivateDocuments(paths: paths, bottleRoot: bottleRoot) else {
            return nil
        }
        let saves = paths.activeWindowsUserDirectory(in: bottleRoot)
            .appendingPathComponent(
                "Documents/My Games/Skyrim Special Edition/Saves",
                isDirectory: true
            )
        return paths.contains(saves, inBottleRoot: bottleRoot)
            && FileManager.default.fileExists(atPath: saves.path) ? saves : nil
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
