import AppKit
import Combine
import Foundation

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var selection: SidebarItem = .games
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
    private let gameServices: [String: GameService]
    private let saveServices: [String: SaveService]
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
        let voiceAudio = VoiceAudioService(
            paths: paths,
            processRunner: runner,
            runtimeManager: runtimeManager
        )
        var gameServices: [String: GameService] = [:]
        var saveServices: [String: SaveService] = [:]
        for descriptor in GameDescriptor.supported {
            gameServices[descriptor.id] = GameService(
                descriptor: descriptor,
                paths: paths,
                steamService: steam,
                bottleManager: bottleManager,
                processRunner: runner,
                runtimeManager: runtimeManager,
                processProbe: processProbe,
                voiceAudioService: voiceAudio
            )
            saveServices[descriptor.id] = SaveService(paths: paths, descriptor: descriptor)
        }
        return LauncherViewModel(
            paths: paths,
            settingsStore: SettingsStore(paths: paths),
            runtimeManager: runtimeManager,
            bottleManager: bottleManager,
            steamService: steam,
            gameServices: gameServices,
            saveServices: saveServices,
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
        gameServices: [String: GameService],
        saveServices: [String: SaveService],
        diagnosticService: DiagnosticService,
        hostPowerProbe: HostPowerProbe
    ) {
        self.paths = paths
        self.settingsStore = settingsStore
        self.runtimeManager = runtimeManager
        self.bottleManager = bottleManager
        self.steamService = steamService
        self.gameServices = gameServices
        self.saveServices = saveServices
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

    // MARK: - Per-game state

    func primaryAction(for descriptor: GameDescriptor) -> PrimaryAction {
        if isBusy { return .unavailable }
        guard snapshot.runtime.isReady else { return .locateRuntime }
        guard snapshot.bottle.isReady else { return .createBottle }
        guard snapshot.steam.isReady else { return .installSteam }
        guard snapshot.game(descriptor).state.isReady else { return .installGame }
        return .play
    }

    func setupJourney(for descriptor: GameDescriptor) -> SetupJourney {
        SetupJourney(snapshot: snapshot, descriptor: descriptor)
    }

    func headline(for descriptor: GameDescriptor) -> String {
        switch primaryAction(for: descriptor) {
        case .locateRuntime:
            paths.bottleOverrideError == nil
                ? "Secunda’s free game engine is missing."
                : "Secunda refused an unsafe test game space."
        case .createBottle: "Prepare a clean realm."
        case .installSteam: "Bring Steam into Secunda."
        case .installGame: "Install \(descriptor.shortTitle) through Steam."
        case .play: "\(descriptor.shortTitle) is installed and ready to launch."
        case .unavailable: progressLabel ?? "Preparing Secunda…"
        }
    }

    func supportingText(for descriptor: GameDescriptor) -> String {
        switch primaryAction(for: descriptor) {
        case .locateRuntime:
            paths.bottleOverrideError
                ?? "This build should include Secunda’s source-built engine. Reinstall the complete Secunda package or use the source build instructions."
        case .createBottle:
            "Secunda creates a separate managed Windows space for Steam, your games, settings, and saves."
        case .installSteam:
            "Steam is downloaded directly from Valve. Secunda never sees or stores your credentials."
        case .installGame:
            "Secunda asks Steam to install your own copy of \(descriptor.shortTitle). Steam confirms the download and shows its progress."
        case .play:
            "Secunda applies its tested settings, asks Steam to authorize your copy, then opens \(descriptor.shortTitle) through its source-built engine."
        case .unavailable:
            "This can take a few minutes. You can leave this window open."
        }
    }

    func gameSettings(for descriptor: GameDescriptor) -> GameSettings {
        settings.game(descriptor)
    }

    func updateGameSettings(_ gameSettings: GameSettings, for descriptor: GameDescriptor) {
        settings.setGame(gameSettings, for: descriptor)
        persistSettings()
    }

    func dlcStates(for descriptor: GameDescriptor) -> [DLCState] {
        gameServices[descriptor.id]?.dlcStates(in: runtime)
            ?? descriptor.dlc.map { DLCState(descriptor: $0, isInstalled: false) }
    }

    // MARK: - Refresh

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
            for descriptor in GameDescriptor.supported {
                var gameSnapshot = GameSnapshot()
                gameSnapshot.state = .missing("Game space unavailable")
                rejected.games[descriptor.id] = gameSnapshot
            }
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

        let steamReady = updated.bottle.isReady
            && steamService.executable(in: locatedRuntime) != nil
        if steamReady {
            updated.steam = .ready("Client files detected")
        }

        var anyGameMissing = false
        for descriptor in GameDescriptor.supported {
            var gameSnapshot = GameSnapshot()
            if steamReady, let service = gameServices[descriptor.id] {
                switch service.installation(in: locatedRuntime) {
                case .installed(let game):
                    gameSnapshot.state = .ready("Game files detected")
                    gameSnapshot.path = game.path
                case .incomplete(let detail):
                    gameSnapshot.state = .warning(detail)
                    anyGameMissing = true
                case .missing:
                    gameSnapshot.state = .missing("Install through Steam")
                    anyGameMissing = true
                }
            } else {
                // Confirmed: without Steam in the game space, nothing is
                // installed — this is a real determination, not a guess.
                gameSnapshot.state = .missing("Install through Steam")
                anyGameMissing = true
            }
            let bottleRoot = locatedRuntime?.bottleRoot ?? paths.bottleRoot
            gameSnapshot.saveCount = saveServices[descriptor.id]?.saveCount(in: bottleRoot) ?? 0
            gameSnapshot.backupCount = saveServices[descriptor.id]?.backupCount ?? 0
            updated.games[descriptor.id] = gameSnapshot
        }

        updated.freeDiskBytes = freeDiskBytes
        updated.lowPowerModeEnabled = lowPowerModeEnabled
        updated.host = HostPreflight.evaluate(
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersion,
            isAppleSilicon: HostPreflight.isAppleSilicon,
            sourceRuntimeProbeSucceeded: locatedRuntime != nil,
            freeDiskBytes: freeDiskBytes,
            needsInstallSpace: anyGameMissing,
            lowPowerModeEnabled: lowPowerModeEnabled
        )
        snapshot = updated
        updateInstallObservation()
    }

    // MARK: - Actions

    func performPrimaryAction(for descriptor: GameDescriptor) {
        switch primaryAction(for: descriptor) {
        case .locateRuntime:
            selection = .settings
            addActivity("The source-built engine is missing. Opened recovery details.", kind: .warning)
        case .createBottle:
            runTask(
                label: "Preparing a separate game space",
                initialProgress: SetupProgress(
                    step: 1,
                    totalSteps: 1,
                    title: "Preparing Secunda",
                    detail: "Creating a separate Windows environment without linking game saves to your Mac Documents folder."
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
        case .installGame:
            requestGameInstall(descriptor)
        case .play:
            play(descriptor)
        case .unavailable:
            break
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

    func play(_ descriptor: GameDescriptor) {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        runTask(
            label: "Preparing \(descriptor.shortTitle) for launch",
            initialProgress: SetupProgress(
                step: 1,
                totalSteps: 6,
                title: "Checking Game Space",
                detail: "Confirming \(descriptor.shortTitle) is not already running before Secunda changes anything."
            )
        ) {
            try await self.launchGame(descriptor, runtime: runtime)
        }
    }

    func requestGameInstall(_ descriptor: GameDescriptor) {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        do {
            try gameServices[descriptor.id]?.requestInstall(
                runtime: runtime,
                diagnostics: settings.enableDiagnostics
            )
            addActivity(
                "Asked Steam to install \(descriptor.shortTitle). Confirm the download inside Steam’s window.",
                kind: .info
            )
            scheduleRefresh()
        } catch {
            present(error)
        }
    }

    func requestGameUninstall(_ descriptor: GameDescriptor) {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        do {
            try gameServices[descriptor.id]?.requestUninstall(
                runtime: runtime,
                diagnostics: settings.enableDiagnostics
            )
            addActivity(
                "Asked Steam to uninstall \(descriptor.shortTitle). Confirm inside Steam’s window; saves stay in place.",
                kind: .info
            )
            scheduleRefresh()
        } catch {
            present(error)
        }
    }

    func requestDLCInstall(_ dlc: DLCDescriptor, for descriptor: GameDescriptor) {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        do {
            try gameServices[descriptor.id]?.requestDLCInstall(
                dlc,
                runtime: runtime,
                diagnostics: settings.enableDiagnostics
            )
            addActivity("Asked Steam to install \(dlc.title). Confirm inside Steam’s window.", kind: .info)
        } catch {
            present(error)
        }
    }

    func stop() {
        guard let runtime, snapshot.steam.isReady else {
            presentedError = "Steam is not installed in Secunda’s selected game space."
            return
        }
        runTask(
            label: "Closing Steam and games",
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

    func verifyGameFiles(_ descriptor: GameDescriptor) {
        guard let runtime else { return }
        do {
            try gameServices[descriptor.id]?.requestVerification(
                runtime: runtime,
                diagnostics: settings.enableDiagnostics
            )
            addActivity("Opened Steam file verification for \(descriptor.shortTitle).", kind: .info)
        } catch {
            present(error)
        }
    }

    func createSaveBackup(_ descriptor: GameDescriptor) {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        do {
            guard let destination = try saveServices[descriptor.id]?.createBackup(in: runtime.bottleRoot) else {
                return
            }
            addActivity("Backed up \(descriptor.shortTitle) saves to \(destination.lastPathComponent).", kind: .success)
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

    // MARK: - Private

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
        try await bottleManager.applyGameCompatibility(
            runtime: runtime,
            diagnostics: settings.enableDiagnostics
        )
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

    private func launchGame(_ descriptor: GameDescriptor, runtime: RuntimeDescriptor) async throws {
        guard let service = gameServices[descriptor.id] else { return }
        let screenPixelWidth = Int(
            (NSScreen.main?.frame.width ?? 0) * (NSScreen.main?.backingScaleFactor ?? 1)
        )
        let outcome = try await service.launch(
            runtime: runtime,
            settings: settings.game(descriptor),
            diagnostics: settings.enableDiagnostics,
            screenPixelWidth: screenPixelWidth,
            progress: { [weak self] stage in
                self?.updateGameLaunchProgress(stage, descriptor: descriptor)
            }
        )
        switch outcome {
        case .started:
            addActivity("\(descriptor.shortTitle) is running through Secunda’s source-built engine.", kind: .success)
        case .alreadyRunning:
            addActivity("\(descriptor.shortTitle) is already running in this game space.", kind: .info)
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
            detail: "Preparing tested audio components before Steam opens."
        )
        try await bottleManager.applyGameCompatibility(
            runtime: runtime,
            diagnostics: settings.enableDiagnostics
        )
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
        addActivity("Steam and every game in this space are closed.", kind: .success)
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

    private func updateGameLaunchProgress(_ stage: GameLaunchStage, descriptor: GameDescriptor) {
        switch stage {
        case .checking:
            updateSetupProgress(
                step: 1,
                title: "Checking Game Space",
                detail: "Confirming \(descriptor.shortTitle) is not already running before Secunda changes anything."
            )
        case .compatibility:
            updateSetupProgress(
                step: 2,
                title: "Applying Compatibility",
                detail: "Preparing the tested graphics, audio, and input settings."
            )
        case .voiceAudio:
            updateSetupProgress(
                step: 3,
                title: "Checking Voice Audio",
                detail: "Confirming Microsoft’s XAudio components so dialogue is audible. First time downloads ~96 MB."
            )
        case .profile:
            updateSetupProgress(
                step: 4,
                title: "Writing Game Settings",
                detail: "Applying your display choices inside Secunda’s selected game space."
            )
        case .steam:
            updateSetupProgress(
                step: 5,
                title: "Waiting for Steam",
                detail: "Steam is authorizing your installed copy of \(descriptor.shortTitle)."
            )
        case .game:
            updateSetupProgress(
                step: 6,
                title: "Starting \(descriptor.shortTitle)",
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
        let anyGamePending = snapshot.steam.isReady
            && GameDescriptor.supported.contains { !snapshot.game($0).state.isReady }
        guard anyGamePending else {
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
                let stillPending = GameDescriptor.supported.contains {
                    !self.snapshot.game($0).state.isReady
                }
                if !stillPending { return }
            }
        }
    }

    private func availableDiskSpace() -> Int64 {
        let values = try? paths.applicationSupport.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
