import AppKit
import Combine
import Foundation
import Sparkle

/// In-app updates through Sparkle. Every update must carry an EdDSA signature
/// that matches `SUPublicEDKey` in Info.plist; Sparkle rejects anything else.
///
/// Secunda's Wine runtime lives inside the app bundle, so replacing the bundle
/// while Steam or a game is still running from it would mix two runtimes.
/// Installation therefore waits until the player agrees to close the game
/// space, and silent install-on-quit is disabled in Info.plist.
@MainActor
final class AppUpdater: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    /// What the last finished check found. Drives the sidebar indicator and
    /// the update row in Settings.
    @Published private(set) var status: Status = .unknown
    @Published private(set) var lastCheckDate: Date?

    enum Status: Equatable {
        /// No check has finished since Secunda opened.
        case unknown
        case upToDate
        case available(version: String)

        var availableVersion: String? {
            if case .available(let version) = self { return version }
            return nil
        }
    }

    /// Whether Secunda checks on its own once a day.
    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// False in `swift run` and other unpackaged builds, which have no feed
    /// URL or public key. Sparkle is never started without both.
    private(set) var isAvailable: Bool

    /// Returns true when Steam or a game is running in the game space.
    var isGameSpaceActive: () async -> Bool = { false }
    /// Closes Steam and every game in the game space.
    var closeGameSpace: () async -> Void = {}

    /// An update the player deferred. Sparkle installs it once Secunda quits,
    /// so quitting must close the game space first.
    private(set) var installsOnQuit = false

    private var controller: SPUStandardUpdaterController?
    private var cancellable: AnyCancellable?

    override init() {
        isAvailable = Self.hasFeedConfiguration(Bundle.main)
        super.init()
        #if DEBUG
        // Design preview for unpackaged debug builds, which have no feed:
        // SECUNDA_PREVIEW_UPDATE=0.9.9 shows the "available" state, and
        // SECUNDA_PREVIEW_UPDATE=none shows "up to date".
        if !isAvailable, let preview = ProcessInfo.processInfo.environment["SECUNDA_PREVIEW_UPDATE"] {
            isAvailable = true
            status = preview == "none" ? .upToDate : .available(version: preview)
            lastCheckDate = Date().addingTimeInterval(-900)
            return
        }
        #endif
        guard isAvailable else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.controller = controller
        lastCheckDate = controller.updater.lastUpdateCheckDate
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    static func hasFeedConfiguration(_ bundle: Bundle) -> Bool {
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https",
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let keyData = Data(base64Encoded: key), keyData.count == 32
        else { return false }
        return true
    }

    /// Called from `applicationShouldTerminate`. Returns true when the quit
    /// must wait for the game space to close.
    func prepareForQuit(reply: @escaping (Bool) -> Void) -> Bool {
        guard installsOnQuit else { return false }
        Task { @MainActor in
            if await self.isGameSpaceActive() {
                await self.closeGameSpace()
            }
            reply(true)
        }
        return true
    }

    /// Ask before closing a running game. Returns true to install now.
    fileprivate func confirmClosingGameSpace() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Close Steam and your game to update?"
        alert.informativeText = "Installing the update closes Steam and every game Secunda is running. Save your game first. Your saves and Steam library stay where they are."
        alert.addButton(withTitle: "Close and Update")
        alert.addButton(withTitle: "Later")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// A scheduled check that finds an update lights the indicator beside the
/// Settings button instead of opening a window over whatever the player is
/// doing. Clicking the indicator, or checking by hand, opens Sparkle's
/// update window as usual.
extension AppUpdater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            self.status = .available(version: version)
        }
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            self.status = .available(version: version)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated {
            self.status = .upToDate
        }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        MainActor.assumeIsolated {
            self.lastCheckDate = self.controller?.updater.lastUpdateCheckDate
        }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        // Sparkle calls its delegate on the main thread.
        MainActor.assumeIsolated {
            Task { @MainActor in
                guard await self.isGameSpaceActive() else {
                    installHandler()
                    return
                }
                // "Later" leaves the update queued. Sparkle installs it after
                // Secunda quits, and quitting closes the game space first.
                guard self.confirmClosingGameSpace() else {
                    self.installsOnQuit = true
                    return
                }
                await self.closeGameSpace()
                installHandler()
            }
        }
        return true
    }
}
