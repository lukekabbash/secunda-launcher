import Foundation

enum ClassicGameCatalogSelfCheck {
    static func failures() -> [String] {
        descriptors.compactMap(validateInstallDetection)
    }

    private static let descriptors: [GameDescriptor] = [
        .insurgency,
        .supremeCommander,
        .forgedAlliance,
        .angelsFallFirst,
        .battlefront2Classic,
        .falloutNewVegas,
        .portal2,
        .halfLife2,
        .enderalSE
    ]

    private static func validateInstallDetection(_ descriptor: GameDescriptor) -> String? {
        let fixture = ClassicGameInstallFixture(descriptor: descriptor)
        defer { fixture.remove() }

        do {
            try fixture.prepare()
        } catch {
            return "\(descriptor.id): fixture setup failed"
        }

        let state = fixture.probe.inspect(
            appID: descriptor.steamAppID,
            executableName: descriptor.executableRelativePath,
            baselineDataFile: descriptor.baselineDataFile,
            displayName: descriptor.shortTitle
        )
        guard case let .installed(executable) = state else {
            return "\(descriptor.id): install was not detected"
        }
        guard executable.standardizedFileURL == fixture.executable.standardizedFileURL else {
            return "\(descriptor.id): executable path did not match"
        }
        return nil
    }
}

private struct ClassicGameInstallFixture {
    let descriptor: GameDescriptor
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("secunda-classic-catalog-\(UUID().uuidString)", isDirectory: true)

    var bottle: URL { root.appendingPathComponent("Bottle", isDirectory: true) }
    var steam: URL { bottle.appendingPathComponent("drive_c/Steam", isDirectory: true) }
    var steamApps: URL { steam.appendingPathComponent("steamapps", isDirectory: true) }
    var gameRoot: URL {
        steamApps.appendingPathComponent("common/\(descriptor.id)", isDirectory: true)
    }
    var executable: URL {
        gameRoot.appendingPathComponent(descriptor.executableRelativePath)
    }
    var manifest: URL {
        steamApps.appendingPathComponent("appmanifest_\(descriptor.steamAppID).acf")
    }
    var probe: SteamInstallProbe {
        SteamInstallProbe(bottleRoot: bottle, steamRoot: steam)
    }

    func prepare() throws {
        try writePlausibleExecutable()
        try writeBaselineMarker()
        try Data(completeManifest.utf8).write(to: manifest)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func writePlausibleExecutable() throws {
        var payload = Data(repeating: 0, count: 4_096)
        payload[0] = 0x4d
        payload[1] = 0x5a
        try write(payload, to: executable)
    }

    private func writeBaselineMarker() throws {
        guard let relativePath = descriptor.baselineDataFile else { return }
        try write(Data([0]), to: gameRoot.appendingPathComponent(relativePath))
    }

    private func write(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file)
    }

    private var completeManifest: String {
        """
        "AppState"
        {
            "appid" "\(descriptor.steamAppID)"
            "StateFlags" "4"
            "installdir" "\(descriptor.id)"
            "BytesToDownload" "100"
            "BytesDownloaded" "100"
            "BytesToStage" "100"
            "BytesStaged" "100"
        }
        """
    }
}
