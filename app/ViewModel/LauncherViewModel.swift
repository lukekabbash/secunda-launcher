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
    @Published private(set) var bottleProcesses: [BottleProcess] = []
    @Published private(set) var activeSessionDescriptorID: String?
    @Published private(set) var launchingDescriptorID: String?

    let paths: SecundaPaths
    private let settingsStore: SettingsStore
    private let runtimeManager: RuntimeManager
    private let bottleManager: BottleManager
    private let steamService: SteamService
    private let gameServices: [String: GameService]
    private let saveServices: [String: SaveService]
    private let diagnosticService: DiagnosticService
    private let hostPowerProbe: HostPowerProbe
    private let bottleProcessInspector: BottleProcessInspector
    private var runtime: RuntimeDescriptor?
    private var installObservationTask: Task<Void, Never>?
    private var expectedInstallStates: [String: InstallExpectation] = [:]
    private var processObservationTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var operationID: UUID?

    private struct InstallExpectation {
        let isInstalled: Bool
        let expiresAt: Date
    }

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
        let bottleProcessInspector = BottleProcessInspector(processRunner: runner)
        let gameWindowProbe = MacGameWindowProbe()
        let dxvk = DXVKService(paths: paths)
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
                voiceAudioService: voiceAudio,
                dxvkService: dxvk,
                bottleProcessInspector: bottleProcessInspector,
                gameWindowProbe: gameWindowProbe
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
            hostPowerProbe: HostPowerProbe(processRunner: runner),
            bottleProcessInspector: bottleProcessInspector
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
        hostPowerProbe: HostPowerProbe,
        bottleProcessInspector: BottleProcessInspector
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
        self.bottleProcessInspector = bottleProcessInspector
        self.settings = settingsStore.load()
        self.snapshot = .empty(paths: paths)
        self.isBusy = true
        self.progressLabel = "Checking the compatibility runtime"

        applyRuntimeSettings()
        Task {
            await refresh()
            startProcessObservation()
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
        if isGameRunning(descriptor) {
            return "\(descriptor.shortTitle) is running."
        }
        return switch primaryAction(for: descriptor) {
        case .locateRuntime:
            paths.bottleOverrideError == nil
                ? "Secunda’s compatibility runtime is missing."
                : "Secunda refused an unsafe test game space."
        case .createBottle: "Prepare a clean realm."
        case .installSteam: "Bring Steam into Secunda."
        case .installGame: "Install \(descriptor.shortTitle) through Steam."
        case .play: "\(descriptor.shortTitle) is installed and ready to launch."
        case .unavailable: progressLabel ?? "Preparing Secunda…"
        }
    }

    func supportingText(for descriptor: GameDescriptor) -> String {
        if isGameRunning(descriptor) {
            return "Playing through Secunda’s source-built Windows compatibility runtime. Save and quit in the game; Stop is the emergency exit."
        }
        return switch primaryAction(for: descriptor) {
        case .locateRuntime:
            paths.bottleOverrideError
                ?? "This build should include Secunda’s source-built Windows compatibility runtime. Reinstall the complete package or use the source build instructions."
        case .createBottle:
            "Secunda creates a separate managed Windows space for Steam, your games, settings, and saves."
        case .installSteam:
            "Steam is downloaded directly from Valve. Secunda never sees or stores your credentials."
        case .installGame:
            "Secunda asks Steam to install your own copy of \(descriptor.shortTitle). Steam confirms the download and shows its progress."
        case .play:
            "Secunda applies its tested settings, asks Steam to authorize your copy, then opens \(descriptor.shortTitle) through its source-built Windows compatibility runtime."
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

    var hasPendingFastSyncChange: Bool {
        settings.useFastSync != settings.activeFastSync
    }

    /// Whether the game has written its Lua prefs file yet — tuning options
    /// can only take effect after that first run.
    func luaPrefsDetected(for descriptor: GameDescriptor) -> Bool {
        guard let relativePath = descriptor.luaPrefsRelativePath else { return false }
        let bottleRoot = runtime?.bottleRoot ?? paths.bottleRoot
        let prefs = paths.activeWindowsUserDirectory(in: bottleRoot)
            .appendingPathComponent(relativePath)
        return paths.contains(prefs, inBottleRoot: bottleRoot)
            && FileManager.default.fileExists(atPath: prefs.path)
    }

    func managedINIProfilesDetected(for descriptor: GameDescriptor) -> Bool {
        gameServices[descriptor.id]?.managedINIProfilesDetected(in: runtime) == true
    }

    // MARK: - Groups

    /// The component a group's card and page act on by default.
    func defaultComponent(for group: GameGroup) -> GameDescriptor {
        if let storedID = settings.groupDefaults[group.id],
           group.componentIDs.contains(storedID),
           let stored = GameDescriptor.descriptor(for: storedID) {
            return stored
        }
        return group.components.first ?? .skyrimSE
    }

    func setDefaultComponent(_ descriptor: GameDescriptor, for group: GameGroup) {
        settings.groupDefaults[group.id] = descriptor.id
        persistSettings()
    }

    func anyComponentInstalled(in group: GameGroup) -> Bool {
        group.components.contains { snapshot.game($0).state.isReady }
    }

    func runningComponent(in group: GameGroup) -> GameDescriptor? {
        let running = group.components.filter { rawGameProcessRunning($0) }
        guard !running.isEmpty else { return nil }
        if running.count == 1 { return running[0] }
        guard let activeSessionDescriptorID else { return nil }
        return running.first { $0.id == activeSessionDescriptorID }
    }

    func isGroupRunning(_ group: GameGroup) -> Bool {
        group.components.contains { rawGameProcessRunning($0) }
    }

    func isGroupLaunching(_ group: GameGroup) -> Bool {
        guard let launchingDescriptorID else { return false }
        return group.componentIDs.contains(launchingDescriptorID)
    }

    func isGroupActive(_ group: GameGroup) -> Bool {
        isGroupLaunching(group) || isGroupRunning(group)
    }

    var anyGameActive: Bool {
        launchingDescriptorID != nil || anyGameRunning
    }

    /// Artwork candidates for a game: any player-supplied image in the
    /// managed Artwork folder wins, then Steam's CDN chain.
    func artworkCandidates(for descriptor: GameDescriptor, hero: Bool) -> [URL] {
        var candidates = customArtwork(for: descriptor, hero: hero)
        candidates += hero ? descriptor.heroArtworkCandidates : descriptor.cardArtworkCandidates
        return candidates
    }

    /// `<managed data>/Artwork/<game-id>.png` (or .jpg/.jpeg), plus an
    /// optional `-hero` variant for the banner.
    private func customArtwork(for descriptor: GameDescriptor, hero: Bool) -> [URL] {
        let directory = paths.artworkDirectory
        let names = hero
            ? ["\(descriptor.id)-hero", descriptor.id]
            : [descriptor.id]
        var urls: [URL] = []
        for name in names {
            for ext in ["png", "jpg", "jpeg"] {
                let candidate = directory.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: candidate.path) {
                    urls.append(candidate)
                }
            }
        }
        return urls
    }

    func revealArtworkFolder() {
        try? FileManager.default.createDirectory(
            at: paths.artworkDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([paths.artworkDirectory])
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
            updated.runtime = .ready("Verified source-built runtime · \(locatedRuntime.version)")
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

        for descriptor in GameDescriptor.supported {
            var gameSnapshot = GameSnapshot()
            if steamReady, let service = gameServices[descriptor.id] {
                switch service.installation(in: locatedRuntime) {
                case .installed(let game):
                    gameSnapshot.state = .ready("Game files detected")
                    gameSnapshot.path = game.path
                case .incomplete(let detail):
                    gameSnapshot.state = .warning(detail)
                case .missing:
                    gameSnapshot.state = .missing("Install through Steam")
                }
            } else {
                // Confirmed: without Steam in the game space, nothing is
                // installed — this is a real determination, not a guess.
                gameSnapshot.state = .missing("Install through Steam")
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
            needsInstallSpace: expectedInstallStates.values.contains { $0.isInstalled },
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
            addActivity("The source-built compatibility runtime is missing. Opened recovery details.", kind: .warning)
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
        guard !isBusy else { return }
        launchingDescriptorID = descriptor.id
        runTask(
            label: "Preparing \(descriptor.shortTitle) for launch",
            initialProgress: SetupProgress(
                step: 1,
                totalSteps: 6,
                title: "Checking Game Space",
                detail: "Confirming \(descriptor.shortTitle) is not already running before Secunda changes anything."
            )
        ) {
            defer { self.launchingDescriptorID = nil }
            try await self.launchGame(descriptor, runtime: runtime)
        }
    }

    func requestGameInstall(_ descriptor: GameDescriptor) {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        if expectedInstallStates[descriptor.id]?.isInstalled == true {
            let message = "\(descriptor.shortTitle) is already queued for installation."
            presentedError = message
            addActivity(message, kind: .info)
            return
        }
        if let capacityError = installCapacityError(for: descriptor) {
            presentedError = capacityError
            addActivity(capacityError, kind: .warning)
            return
        }
        observeInstallState(for: descriptor, isInstalled: true)
        Task {
            do {
                try await activatePendingRuntimeSettingsIfQuiet(runtime)
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
                expectedInstallStates.removeValue(forKey: descriptor.id)
                updateInstallObservation()
                present(error)
            }
        }
    }

    func requestGameUninstall(_ descriptor: GameDescriptor) {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        Task {
            do {
                try await activatePendingRuntimeSettingsIfQuiet(runtime)
                try gameServices[descriptor.id]?.requestUninstall(
                    runtime: runtime,
                    diagnostics: settings.enableDiagnostics
                )
                addActivity(
                    "Asked Steam to uninstall \(descriptor.shortTitle). Confirm inside Steam’s window; saves stay in place.",
                    kind: .info
                )
                observeInstallState(for: descriptor, isInstalled: false)
                scheduleRefresh()
            } catch {
                present(error)
            }
        }
    }

    func requestDLCInstall(_ dlc: DLCDescriptor, for descriptor: GameDescriptor) {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        Task {
            do {
                try await activatePendingRuntimeSettingsIfQuiet(runtime)
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
                detail: "Closing every Windows app here, then confirming Secunda’s runtime has stopped."
            )
        ) {
            try await self.shutdown(runtime)
        }
    }

    /// Hard per-game stop for hung or orphaned processes. Skips Wine's
    /// graceful shutdown entirely, so it works when wineserver is dead.
    func forceStopGame(_ descriptor: GameDescriptor) {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        runTask(label: "Force-stopping \(descriptor.shortTitle)") {
            let killed = try await self.gameServices[descriptor.id]?
                .forceStop(runtime: runtime) ?? 0
            self.addActivity(
                killed > 0
                    ? "Force-stopped \(killed) \(descriptor.shortTitle) process\(killed == 1 ? "" : "es")."
                    : "Nothing to stop — no \(descriptor.shortTitle) processes were running.",
                kind: killed > 0 ? .success : .info
            )
            self.refreshBottleProcesses()
        }
    }

    func forceStopGroup(_ group: GameGroup) {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        runTask(label: "Force-stopping \(group.shortTitle)") {
            let images = group.components.flatMap(\.processImageNames)
            let processes = try await self.bottleProcessInspector
                .processesInBottle(runtime: runtime)
                .filter { BottleProcessInspector.matchesImages($0.command, images: images) }
            await self.bottleProcessInspector.forceKill(processes)
            if let activeSessionDescriptorID = self.activeSessionDescriptorID,
               group.componentIDs.contains(activeSessionDescriptorID) {
                self.activeSessionDescriptorID = nil
            }
            self.addActivity(
                processes.isEmpty
                    ? "Nothing to stop — no \(group.shortTitle) process was running."
                    : "Force-stopped \(group.shortTitle).",
                kind: processes.isEmpty ? .info : .success
            )
            self.refreshBottleProcesses()
        }
    }

    /// The library's active-card Stop control must remain available during
    /// launch handoff. Cancel the in-flight launch before closing the shared
    /// Windows space so a late Steam handoff cannot reopen the title.
    func stopActiveGameSpace() {
        guard anyGameActive else { return }
        operationTask?.cancel()
        operationTask = nil
        operationID = nil
        launchingDescriptorID = nil
        isBusy = false
        progressLabel = nil
        setupProgress = nil
        stop()
    }

    /// Refresh the on-demand process list shown in Launcher Settings.
    func refreshBottleProcesses() {
        guard let runtime else {
            bottleProcesses = []
            activeSessionDescriptorID = nil
            return
        }
        Task {
            let processes = (try? await bottleProcessInspector.runningProcesses(runtime: runtime)) ?? []
            bottleProcesses = processes
            if let activeSessionDescriptorID,
               let descriptor = GameDescriptor.descriptor(for: activeSessionDescriptorID),
               !Self.processes(processes, match: descriptor) {
                self.activeSessionDescriptorID = nil
            }
        }
    }

    /// Live host-side check: is this game's process actually running? Drives
    /// the stop controls, which must vanish once the player quits.
    func isGameRunning(_ descriptor: GameDescriptor) -> Bool {
        guard rawGameProcessRunning(descriptor) else { return false }
        guard let group = GameGroup.group(containing: descriptor.id) else { return true }
        let matchingComponents = group.components.filter { rawGameProcessRunning($0) }
        guard matchingComponents.count > 1 else { return true }
        return activeSessionDescriptorID == descriptor.id
    }

    var anyGameRunning: Bool {
        GameDescriptor.supported.contains { rawGameProcessRunning($0) }
    }

    private func rawGameProcessRunning(_ descriptor: GameDescriptor) -> Bool {
        Self.processes(bottleProcesses, match: descriptor)
    }

    private static func processes(
        _ processes: [BottleProcess],
        match descriptor: GameDescriptor
    ) -> Bool {
        processes.contains { process in
            BottleProcessInspector.matchesImages(
                process.command,
                images: descriptor.processImageNames
            )
        }
    }

    /// Keep the process snapshot fresh so running/stopped state tracks
    /// reality within a few seconds of a game quitting.
    func startProcessObservation() {
        guard processObservationTask == nil else { return }
        processObservationTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshBottleProcesses()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Force-stop specific processes from the Settings list.
    func forceStopProcesses(_ processes: [BottleProcess]) {
        guard !processes.isEmpty else { return }
        Task {
            await bottleProcessInspector.forceKill(processes)
            addActivity(
                "Force-stopped \(processes.count) game-space process\(processes.count == 1 ? "" : "es").",
                kind: .success
            )
            refreshBottleProcesses()
            await refresh()
        }
    }

    /// The whole-bottle hammer: kill every game-space process, then ask any
    /// surviving wineserver to shut down. This is the recovery path for the
    /// orphaned-processes-block-macOS-restart scenario.
    func forceStopEverything() {
        guard let runtime else {
            presentedError = "A compatible runtime is not available."
            return
        }
        runTask(label: "Force-stopping all game-space processes") {
            let processes = try await self.bottleProcessInspector.runningProcesses(runtime: runtime)
            await self.bottleProcessInspector.forceKill(processes)
            let wineserver = runtime.wineExecutable
                .deletingLastPathComponent()
                .appendingPathComponent("wineserver")
            _ = try? await self.bottleManager.requestWineserverExit(
                wineserver: wineserver,
                runtime: runtime,
                diagnostics: self.settings.enableDiagnostics
            )
            self.addActivity(
                processes.isEmpty
                    ? "Nothing to stop — the game space is already quiet."
                    : "Force-stopped \(processes.count) game-space process\(processes.count == 1 ? "" : "es").",
                kind: processes.isEmpty ? .info : .success
            )
            try await self.activatePendingRuntimeSettingsIfQuiet(runtime)
            self.refreshBottleProcesses()
        }
    }

    func verifyGameFiles(_ descriptor: GameDescriptor) {
        guard let runtime else { return }
        Task {
            do {
                try await activatePendingRuntimeSettingsIfQuiet(runtime)
                try gameServices[descriptor.id]?.requestVerification(
                    runtime: runtime,
                    diagnostics: settings.enableDiagnostics
                )
                addActivity("Opened Steam file verification for \(descriptor.shortTitle).", kind: .info)
            } catch {
                present(error)
            }
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

    /// Push only the active launcher-wide choice into process environments.
    /// The requested value may remain queued while wineserver is alive.
    private func applyRuntimeSettings() {
        runtimeManager.useFastSync = settings.activeFastSync
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
        try await activatePendingRuntimeSettingsIfQuiet(runtime)
        try await bottleManager.initialize(runtime: runtime, diagnostics: settings.enableDiagnostics)
        addActivity("Secunda’s separate game space is ready.", kind: .success)
    }

    private func installSteam() async throws {
        guard let runtime else { throw CocoaError(.fileNoSuchFile) }
        try await activatePendingRuntimeSettingsIfQuiet(runtime)
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
        try await activatePendingRuntimeSettingsIfQuiet(runtime)
        let displayGeometry = descriptor.launchProfile.displayCoordinatePolicy == .backingPixels
            ? HostDisplayGeometryProbe.wineMainDisplay()
            : HostDisplayGeometryProbe.geometry(for: NSScreen.main)
        let outcome = try await service.launch(
            runtime: runtime,
            settings: settings.game(descriptor),
            diagnostics: settings.enableDiagnostics,
            displayGeometry: displayGeometry,
            progress: { [weak self] stage in
                self?.updateGameLaunchProgress(stage, descriptor: descriptor)
            }
        )
        switch outcome {
        case .started:
            activeSessionDescriptorID = descriptor.id
            addActivity(
                "\(descriptor.shortTitle) is running through Secunda’s source-built Windows compatibility runtime.",
                kind: .success
            )
        case .alreadyRunning:
            addActivity("\(descriptor.shortTitle) is already running in this game space.", kind: .info)
        }
    }

    private func launchSteam(_ runtime: RuntimeDescriptor) async throws {
        try await activatePendingRuntimeSettingsIfQuiet(runtime)
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
        // Graceful first; then sweep anything the Wine-IPC path cannot
        // reach (orphaned processes whose wineserver already died).
        var gracefulError: Error?
        do {
            try await bottleManager.shutdown(runtime: runtime, diagnostics: settings.enableDiagnostics)
        } catch {
            gracefulError = error
        }
        let leftovers = (try? await bottleProcessInspector.runningProcesses(runtime: runtime)) ?? []
        if !leftovers.isEmpty {
            await bottleProcessInspector.forceKill(leftovers)
            addActivity(
                "Force-stopped \(leftovers.count) process\(leftovers.count == 1 ? "" : "es") the graceful shutdown couldn’t reach.",
                kind: .warning
            )
        } else if let gracefulError {
            throw gracefulError
        }
        try await activatePendingRuntimeSettingsIfQuiet(runtime)
        addActivity("Steam and every game in this space are closed.", kind: .success)
    }

    /// Promote a queued sync mode only after a fresh host-process scan proves
    /// that no process can still be attached to the old wineserver mode.
    private func activatePendingRuntimeSettingsIfQuiet(
        _ runtime: RuntimeDescriptor
    ) async throws {
        guard settings.activeFastSync != settings.useFastSync else { return }
        guard try await bottleProcessInspector.runningProcesses(runtime: runtime).isEmpty else { return }

        var updated = settings
        updated.activeFastSync = updated.useFastSync
        try settingsStore.save(updated)
        settings = updated
        applyRuntimeSettings()
        addActivity(
            "Fast synchronization is now \(updated.activeFastSync ? "on" : "off") for this game space.",
            kind: .info
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
        let currentOperationID = UUID()
        operationID = currentOperationID
        operationTask = Task {
            do {
                try await operation()
                await refresh()
            } catch {
                if !Task.isCancelled {
                    present(error)
                }
            }
            if operationID == currentOperationID {
                isBusy = false
                progressLabel = nil
                setupProgress = nil
                operationTask = nil
                operationID = nil
            }
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
                detail: "Opening the game through Secunda’s verified source-built Windows compatibility runtime."
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
        let now = Date()
        expectedInstallStates = expectedInstallStates.filter { gameID, expectation in
            guard now < expectation.expiresAt,
                  let descriptor = GameDescriptor.descriptor(for: gameID)
            else {
                return false
            }
            return snapshot.game(descriptor).state.isReady != expectation.isInstalled
        }
        guard snapshot.steam.isReady, !expectedInstallStates.isEmpty else {
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
            }
        }
    }

    private func observeInstallState(
        for descriptor: GameDescriptor,
        isInstalled: Bool
    ) {
        expectedInstallStates[descriptor.id] = InstallExpectation(
            isInstalled: isInstalled,
            expiresAt: Date().addingTimeInterval(20 * 60)
        )
        updateInstallObservation()
    }

    private func installCapacityError(for descriptor: GameDescriptor) -> String? {
        let pending: [GameDescriptor] = expectedInstallStates.compactMap { gameID, expectation in
            guard expectation.isInstalled else { return nil }
            return GameDescriptor.descriptor(for: gameID)
        }
        guard let requiredBytes = InstallSpacePolicy.requiredFreeBytes(
            for: descriptor,
            pending: pending
        ) else {
            return nil
        }
        let freeBytes = availableDiskSpace()
        guard freeBytes < requiredBytes else { return nil }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let required = formatter.string(fromByteCount: requiredBytes)
        let available = formatter.string(fromByteCount: freeBytes)
        return "\(descriptor.shortTitle) and the queued downloads need about \(required) free so macOS and Steam keep a safe reserve. \(available) is currently available."
    }

    private func availableDiskSpace() -> Int64 {
        let values = try? paths.applicationSupport.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
