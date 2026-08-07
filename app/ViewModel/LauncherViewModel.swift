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
    private let hostPowerProbe: HostPowerProbe
    private var runtime: RuntimeDescriptor?
    private var installObservationTask: Task<Void, Never>?

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
        let processProbe = WindowsProcessProbe(
            processRunner: runner,
            runtimeManager: runtimeManager
        )
        return LauncherViewModel(
            paths: paths,
            settingsStore: SettingsStore(paths: paths),
            runtimeManager: runtimeManager,
            bottleManager: bottleManager,
            steamService: steam,
            skyrimService: SkyrimService(
                paths: paths,
                steamService: steam,
                bottleManager: bottleManager,
                processRunner: runner,
                runtimeManager: runtimeManager,
                processProbe: processProbe
            ),
            saveService: SaveService(paths: paths),
            diagnosticService: DiagnosticService(paths: paths),
            hostPowerProbe: HostPowerProbe(processRunner: runner)
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
        diagnosticService: DiagnosticService,
        hostPowerProbe: HostPowerProbe
    ) {
        self.paths = paths
        self.settingsStore = settingsStore
        self.runtimeManager = runtimeManager
        self.bottleManager = bottleManager
        self.steamService = steamService
        self.skyrimService = skyrimService
        self.saveService = saveService
        self.diagnosticService = diagnosticService
        self.hostPowerProbe = hostPowerProbe
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

    var setupJourney: SetupJourney {
        SetupJourney(snapshot: snapshot)
    }

    var headline: String {
        switch primaryAction {
        case .locateRuntime:
            paths.bottleOverrideError == nil
                ? "Secunda’s free game engine is missing."
                : "Secunda refused an unsafe test game space."
        case .createBottle: "Prepare a clean realm."
        case .installSteam: "Bring Steam into Secunda."
        case .openSteam: "Install Skyrim through Steam."
        case .play: "Skyrim is installed and ready to launch."
        case .unavailable: progressLabel ?? "Preparing Secunda…"
        }
    }

    var supportingText: String {
        switch primaryAction {
        case .locateRuntime:
            paths.bottleOverrideError
                ?? "This build should include Secunda’s source-built engine. Reinstall the complete Secunda package or use the source build instructions."
        case .createBottle:
            "Secunda creates a separate managed Windows space for Steam, Skyrim, settings, and saves."
        case .installSteam:
            "Steam is downloaded directly from Valve. Secunda never sees or stores your credentials."
        case .openSteam:
            "Sign in to your own Steam account, install Skyrim Special Edition, then return here."
        case .play:
            "Secunda applies its tested settings, asks Steam to authorize your copy, then opens Skyrim through its source-built engine."
        case .unavailable:
            "This can take a few minutes. You can leave this window open."
        }
    }

    func refresh() async {
        let lowPowerModeEnabled = await hostPowerProbe.lowPowerModeEnabled() ?? false
        guard paths.bottleOverrideError == nil else {
            runtime = nil
            var rejected = LauncherSnapshot.empty(paths: paths)
            rejected.host = HostPreflight.evaluate(
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersion,
                isAppleSilicon: HostPreflight.isAppleSilicon,
                sourceRuntimeProbeSucceeded: false,
                freeDiskBytes: availableDiskSpace(),
                needsInstallSpace: true,
                lowPowerModeEnabled: lowPowerModeEnabled
            )
            rejected.runtime = .failed("Unsafe test game-space name rejected")
            rejected.bottle = .failed("No fallback game space was opened")
            snapshot = rejected
            return
        }
        let locatedRuntime = await runtimeManager.locate()
        runtime = locatedRuntime

        var updated = LauncherSnapshot.empty(paths: paths)
        let freeDiskBytes = availableDiskSpace()
        if let locatedRuntime {
            updated.runtime = .ready("Verified source-only engine · \(locatedRuntime.version)")
            updated.runtimePath = locatedRuntime.wineExecutable.path
            updated.bottlePath = locatedRuntime.bottleRoot.path
        }
        updated.bottle = bottleManager.isInitialized(runtime: locatedRuntime)
            ? .ready(paths.usesBottleOverride
                ? "Separate test space · \(paths.bottleName)"
                : "Separate game space")
            : .missing("Not prepared")
        if updated.bottle.isReady, steamService.executable(in: locatedRuntime) != nil {
            updated.steam = .ready("Client files detected")
            switch skyrimService.installation(in: locatedRuntime) {
            case .installed(let game):
                updated.game = .ready("Game files detected")
                updated.gamePath = game.path
            case .incomplete(let detail):
                updated.game = .warning(detail)
            case .missing:
                updated.game = .missing("Install through Steam")
            }
        }
        updated.saveCount = saveService.saveCount(in: locatedRuntime?.bottleRoot ?? paths.bottleRoot)
        updated.backupCount = saveService.backupCount
        updated.freeDiskBytes = freeDiskBytes
        updated.lowPowerModeEnabled = lowPowerModeEnabled
        updated.host = HostPreflight.evaluate(
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersion,
            isAppleSilicon: HostPreflight.isAppleSilicon,
            sourceRuntimeProbeSucceeded: locatedRuntime != nil,
            freeDiskBytes: freeDiskBytes,
            needsInstallSpace: !updated.game.isReady,
            lowPowerModeEnabled: lowPowerModeEnabled
        )
        snapshot = updated
        updateInstallObservation()
    }

    func performPrimaryAction() {
        switch primaryAction {
        case .locateRuntime:
            selection = .support
            addActivity("The source-built engine is missing. Opened recovery details.", kind: .warning)
        case .createBottle:
            runTask(
                label: "Preparing a separate game space",
                initialProgress: SetupProgress(
                    step: 1,
                    totalSteps: 1,
                    title: "Preparing Secunda",
                    detail: "Creating a separate Windows environment without linking Skyrim saves to your Mac Documents folder."
                )
            ) { try await self.createBottle() }
        case .installSteam:
            runTask(
                label: "Downloading and installing Steam",
                initialProgress: SetupProgress(
                    step: 1,
                    totalSteps: 4,
                    title: "Checking the bottle",
                    detail: "Confirming Secunda’s selected game space is ready."
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
        runTask(
            label: "Preparing Steam",
            initialProgress: SetupProgress(
                step: 1,
                totalSteps: 3,
                title: "Checking Private Space",
                detail: "Confirming Steam is using Secunda’s selected game space."
            )
        ) {
            try await self.launchSteam(runtime)
        }
    }

    func play() {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        runTask(
            label: "Preparing Skyrim for launch",
            initialProgress: SetupProgress(
                step: 1,
                totalSteps: 5,
                title: "Checking Game Space",
                detail: "Confirming Skyrim is not already running before Secunda changes anything."
            )
        ) {
            try await self.launchSkyrim(runtime)
        }
    }

    func stop() {
        guard let runtime, snapshot.steam.isReady else {
            presentedError = "Steam is not installed in Secunda’s selected game space."
            return
        }
        runTask(
            label: "Closing Steam and Skyrim",
            initialProgress: SetupProgress(
                step: 1,
                totalSteps: 1,
                title: "Closing the Game Space",
                detail: "Closing every Windows app here, then confirming Secunda’s engine has stopped."
            )
        ) {
            try await self.shutdown(runtime)
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
        addActivity("Secunda’s separate game space is ready.", kind: .success)
    }

    private func installSteam() async throws {
        guard let runtime else { throw CocoaError(.fileNoSuchFile) }
        updateSetupProgress(
            step: 1,
            title: "Checking the bottle",
            detail: "Confirming Secunda’s selected game space is ready."
        )
        if !bottleManager.isInitialized(runtime: runtime) {
            progressLabel = "Preparing the separate game space"
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
            detail: "Copying the Steam client into Secunda’s separate game space."
        )
        try await steamService.install(runtime: runtime, diagnostics: settings.enableDiagnostics)
        progressLabel = "Opening Steam login"
        updateSetupProgress(
            step: 4,
            title: "Opening Steam",
            detail: "Starting Steam’s own secure login window."
        )
        try steamService.launch(runtime: runtime, diagnostics: settings.enableDiagnostics)
        addActivity("Steam launch requested. Sign in only inside Steam’s own window.", kind: .info)
        scheduleRefresh()
    }

    private func launchSkyrim(_ runtime: RuntimeDescriptor) async throws {
        let outcome = try await skyrimService.launch(
            runtime: runtime,
            settings: settings,
            diagnostics: settings.enableDiagnostics,
            progress: { [weak self] stage in
                self?.updateSkyrimLaunchProgress(stage)
            }
        )
        switch outcome {
        case .started:
            addActivity("Skyrim is running through Secunda’s source-built engine.", kind: .success)
        case .alreadyRunning:
            addActivity("Skyrim is already running in this game space.", kind: .info)
        }
    }

    private func launchSteam(_ runtime: RuntimeDescriptor) async throws {
        updateSetupProgress(
            step: 1,
            title: "Checking Private Space",
            detail: "Confirming Steam is using Secunda’s selected game space."
        )
        if !bottleManager.isInitialized(runtime: runtime) {
            try await bottleManager.initialize(runtime: runtime, diagnostics: settings.enableDiagnostics)
        }
        updateSetupProgress(
            step: 2,
            title: "Applying Compatibility",
            detail: "Preparing Skyrim’s tested audio components before Steam opens."
        )
        try await prepareSkyrimCompatibility(runtime)
        updateSetupProgress(
            step: 3,
            title: "Requesting Steam",
            detail: "Starting Steam with Secunda’s visible-window compatibility settings."
        )
        try steamService.launch(runtime: runtime, diagnostics: settings.enableDiagnostics)
        addActivity("Steam launch requested inside Secunda’s selected game space.", kind: .info)
        scheduleRefresh()
    }

    private func shutdown(_ runtime: RuntimeDescriptor) async throws {
        try await bottleManager.shutdown(runtime: runtime, diagnostics: settings.enableDiagnostics)
        addActivity("Steam and Skyrim are closed in this game space.", kind: .success)
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

    private func updateSkyrimLaunchProgress(_ stage: SkyrimLaunchStage) {
        switch stage {
        case .checking:
            updateSetupProgress(
                step: 1,
                title: "Checking Game Space",
                detail: "Confirming Skyrim is not already running before Secunda changes anything."
            )
        case .compatibility:
            updateSetupProgress(
                step: 2,
                title: "Applying Compatibility",
                detail: "Preparing the tested graphics, audio, and input settings."
            )
        case .profile:
            updateSetupProgress(
                step: 3,
                title: "Writing Game Settings",
                detail: "Applying your display choices inside Secunda’s selected game space."
            )
        case .steam:
            updateSetupProgress(
                step: 4,
                title: "Waiting for Steam",
                detail: "Steam is authorizing your installed copy of Skyrim Special Edition."
            )
        case .game:
            updateSetupProgress(
                step: 5,
                title: "Starting Skyrim",
                detail: "Opening the game through Secunda’s verified source-built engine."
            )
        }
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

    private func updateInstallObservation() {
        guard snapshot.steam.isReady, !snapshot.game.isReady else {
            installObservationTask?.cancel()
            installObservationTask = nil
            return
        }
        guard installObservationTask == nil else { return }

        installObservationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
                if self.snapshot.game.isReady { return }
            }
        }
    }

    private func availableDiskSpace() -> Int64 {
        let values = try? paths.applicationSupport.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
