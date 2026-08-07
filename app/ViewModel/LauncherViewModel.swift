import AppKit
import Combine
import Foundation

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var selection: LauncherSection = .play
    @Published private(set) var snapshot: LauncherSnapshot
    @Published private(set) var activities: [ActivityEntry] = []
    @Published private(set) var isBusy = false
    @Published private(set) var progressLabel: String?
    @Published private(set) var setupProgress: SetupProgress?
    @Published var settings: LauncherSettings
    @Published var presentedError: String?

    let paths: SecundaPaths
    private let settingsStore: SettingsStore
    private let runtimeManager: RuntimeManager
    private let bottleManager: BottleManager
    private let steamService: SteamService
    private let skyrimService: SkyrimService
    private let saveService: SaveService
    private let diagnosticService: DiagnosticService
    private var runtime: RuntimeDescriptor?

    static func live() -> LauncherViewModel {
        let paths = SecundaPaths()
        let runner = ProcessRunner()
        let runtimeManager = RuntimeManager(paths: paths, processRunner: runner)
        let bottleManager = BottleManager(
            paths: paths,
            processRunner: runner,
            runtimeManager: runtimeManager
        )
        let steam = SteamService(paths: paths, processRunner: runner, runtimeManager: runtimeManager)
        return LauncherViewModel(
            paths: paths,
            settingsStore: SettingsStore(paths: paths),
            runtimeManager: runtimeManager,
            bottleManager: bottleManager,
            steamService: steam,
            skyrimService: SkyrimService(
                paths: paths,
                steamService: steam,
                bottleManager: bottleManager
            ),
            saveService: SaveService(paths: paths),
            diagnosticService: DiagnosticService(paths: paths)
        )
    }

    init(
        paths: SecundaPaths,
        settingsStore: SettingsStore,
        runtimeManager: RuntimeManager,
        bottleManager: BottleManager,
        steamService: SteamService,
        skyrimService: SkyrimService,
        saveService: SaveService,
        diagnosticService: DiagnosticService
    ) {
        self.paths = paths
        self.settingsStore = settingsStore
        self.runtimeManager = runtimeManager
        self.bottleManager = bottleManager
        self.steamService = steamService
        self.skyrimService = skyrimService
        self.saveService = saveService
        self.diagnosticService = diagnosticService
        self.settings = settingsStore.load()
        self.snapshot = .empty(paths: paths)
        self.isBusy = true
        self.progressLabel = "Checking the game engine"

        Task {
            await refresh()
            isBusy = false
            progressLabel = nil
        }
    }

    var primaryAction: PrimaryAction {
        if isBusy { return .unavailable }
        guard snapshot.runtime.isReady else { return .locateRuntime }
        guard snapshot.bottle.isReady else { return .createBottle }
        guard snapshot.steam.isReady else { return .installSteam }
        guard snapshot.game.isReady else { return .openSteam }
        return .play
    }

    var headline: String {
        switch primaryAction {
        case .locateRuntime: "Secunda’s free game engine is missing."
        case .createBottle: "Prepare a clean realm."
        case .installSteam: "Bring Steam into Secunda."
        case .openSteam: "Install Skyrim through Steam."
        case .play: "The road north is open."
        case .unavailable: progressLabel ?? "Preparing Secunda…"
        }
    }

    var supportingText: String {
        switch primaryAction {
        case .locateRuntime:
            "This build should include Secunda’s source-built engine. Reinstall the complete Secunda package or use the source build instructions."
        case .createBottle:
            "Secunda keeps Steam, Skyrim, settings, and logs inside one isolated managed bottle."
        case .installSteam:
            "Steam is downloaded directly from Valve. Secunda never sees or stores your credentials."
        case .openSteam:
            "Sign in to your own Steam account, install Skyrim Special Edition, then return here."
        case .play:
            "Launch your verified Steam copy with Secunda’s tested Mac profile."
        case .unavailable:
            "This can take a few minutes. You can leave this window open."
        }
    }

    func refresh() async {
        let locatedRuntime = await runtimeManager.locate()
        runtime = locatedRuntime

        var updated = LauncherSnapshot.empty(paths: paths)
        if let locatedRuntime {
            updated.runtime = .ready("\(locatedRuntime.origin.rawValue) · \(locatedRuntime.version)")
            updated.runtimePath = locatedRuntime.wineExecutable.path
            updated.bottlePath = locatedRuntime.bottleRoot.path
        }
        updated.bottle = bottleManager.isInitialized(runtime: locatedRuntime)
            ? .ready("Isolated Skyrim bottle")
            : .missing("Not created")
        if let steam = steamService.executable(in: locatedRuntime) {
            updated.steam = .ready("Installed")
            if let game = skyrimService.executable(in: locatedRuntime) {
                updated.game = .ready("Skyrim Special Edition")
                updated.gamePath = game.path
            } else {
                updated.game = .missing("Install through Steam")
            }
            _ = steam
        }
        updated.saveCount = saveService.saveCount(in: locatedRuntime?.bottleRoot ?? paths.bottleRoot)
        updated.backupCount = saveService.backupCount
        updated.freeDiskBytes = availableDiskSpace()
        snapshot = updated
    }

    func performPrimaryAction() {
        switch primaryAction {
        case .locateRuntime:
            presentedError = "Secunda’s source-built runtime is unavailable. Reinstall the complete app or build Runtime/wine from the included source instructions."
        case .createBottle:
            runTask(
                label: "Preparing the Skyrim bottle",
                initialProgress: SetupProgress(
                    step: 1,
                    totalSteps: 1,
                    title: "Preparing Secunda",
                    detail: "Creating an isolated Windows environment for Steam and the game."
                )
            ) { try await self.createBottle() }
        case .installSteam:
            runTask(
                label: "Downloading and installing Steam",
                initialProgress: SetupProgress(
                    step: 1,
                    totalSteps: 4,
                    title: "Checking the bottle",
                    detail: "Confirming the isolated environment is ready."
                )
            ) { try await self.installSteam() }
        case .openSteam: openSteam()
        case .play: play()
        case .unavailable: break
        }
    }

    func openSteam() {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        runTask(label: "Opening Steam") {
            try await self.launchSteam(runtime)
        }
    }

    func play() {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        runTask(label: "Preparing Skyrim for launch") {
            try await self.launchSkyrim(runtime)
        }
    }

    func verifyGameFiles() {
        guard let runtime else { return }
        do {
            try skyrimService.requestVerification(runtime: runtime, diagnostics: settings.enableDiagnostics)
            addActivity("Opened Steam file verification for Skyrim.", kind: .info)
        } catch {
            present(error)
        }
    }

    func createSaveBackup() {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        do {
            let destination = try saveService.createBackup(in: runtime.bottleRoot)
            addActivity("Backed up saves to \(destination.lastPathComponent).", kind: .success)
            Task { await refresh() }
        } catch {
            present(error)
        }
    }

    func persistSettings() {
        do {
            try settingsStore.save(settings)
        } catch {
            present(error)
        }
    }

    func revealApplicationData() {
        try? paths.prepareManagedDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([paths.applicationSupport])
    }

    func revealLogs() {
        try? paths.prepareManagedDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([paths.logsDirectory])
    }

    var diagnosticReport: String {
        diagnosticService.report(snapshot: snapshot)
    }

    var latestLogExcerpt: String {
        diagnosticService.latestLogExcerpt()
    }

    private func createBottle() async throws {
        guard let runtime else { throw CocoaError(.fileNoSuchFile) }
        try await bottleManager.initialize(runtime: runtime, diagnostics: settings.enableDiagnostics)
        addActivity("Created the isolated Skyrim bottle.", kind: .success)
    }

    private func installSteam() async throws {
        guard let runtime else { throw CocoaError(.fileNoSuchFile) }
        updateSetupProgress(
            step: 1,
            title: "Checking the bottle",
            detail: "Confirming the isolated environment is ready."
        )
        if !bottleManager.isInitialized(runtime: runtime) {
            progressLabel = "Preparing the Skyrim bottle"
            try await bottleManager.initialize(runtime: runtime, diagnostics: settings.enableDiagnostics)
        }
        try await prepareSkyrimCompatibility(runtime)
        progressLabel = "Downloading Steam directly from Valve"
        updateSetupProgress(
            step: 2,
            title: "Downloading Steam",
            detail: "Receiving the official installer directly from Valve over HTTPS."
        )
        _ = try await steamService.downloadInstaller()
        progressLabel = "Installing Steam"
        updateSetupProgress(
            step: 3,
            title: "Installing Steam",
            detail: "Copying the Steam client into Secunda’s isolated bottle."
        )
        try await steamService.install(runtime: runtime, diagnostics: settings.enableDiagnostics)
        progressLabel = "Opening Steam login"
        updateSetupProgress(
            step: 4,
            title: "Opening Steam",
            detail: "Starting Steam’s own secure login window."
        )
        try steamService.launch(runtime: runtime, diagnostics: settings.enableDiagnostics)
        addActivity("Installed and opened Steam. Sign in in the Steam window.", kind: .success)
        scheduleRefresh()
    }

    private func launchSkyrim(_ runtime: RuntimeDescriptor) async throws {
        try await skyrimService.launch(
            runtime: runtime,
            settings: settings,
            diagnostics: settings.enableDiagnostics
        )
        addActivity("Asked Steam to launch Skyrim Special Edition.", kind: .success)
    }

    private func launchSteam(_ runtime: RuntimeDescriptor) async throws {
        if !bottleManager.isInitialized(runtime: runtime) {
            try await bottleManager.initialize(runtime: runtime, diagnostics: settings.enableDiagnostics)
        }
        try await prepareSkyrimCompatibility(runtime)
        try steamService.launch(runtime: runtime, diagnostics: settings.enableDiagnostics)
        addActivity("Opened Steam inside the Secunda bottle.", kind: .success)
        scheduleRefresh()
    }

    private func prepareSkyrimCompatibility(_ runtime: RuntimeDescriptor) async throws {
        try await bottleManager.applyGameCompatibility(
            runtime: runtime,
            diagnostics: settings.enableDiagnostics
        )
    }

    private func runTask(
        label: String,
        initialProgress: SetupProgress? = nil,
        operation: @escaping () async throws -> Void
    ) {
        guard !isBusy else { return }
        isBusy = true
        progressLabel = label
        setupProgress = initialProgress
        addActivity(label, kind: .info)
        Task {
            do {
                try await operation()
                await refresh()
            } catch {
                present(error)
            }
            isBusy = false
            progressLabel = nil
            setupProgress = nil
        }
    }

    private func updateSetupProgress(step: Int, title: String, detail: String) {
        let totalSteps = setupProgress?.totalSteps ?? 1
        setupProgress = SetupProgress(
            step: step,
            totalSteps: totalSteps,
            title: title,
            detail: detail
        )
    }

    private func present(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        presentedError = message
        addActivity(message, kind: .error)
    }

    private func addActivity(_ message: String, kind: ActivityEntry.Kind) {
        activities.insert(ActivityEntry(date: Date(), message: message, kind: kind), at: 0)
        activities = Array(activities.prefix(20))
    }

    private func scheduleRefresh() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            await refresh()
        }
    }

    private func availableDiskSpace() -> Int64 {
        let values = try? paths.applicationSupport.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
