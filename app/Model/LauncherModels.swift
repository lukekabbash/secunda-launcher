import Foundation

enum LauncherSection: String, CaseIterable, Identifiable {
    case play
    case saves
    case settings
    case support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .play: "Play"
        case .saves: "Saves"
        case .settings: "Settings"
        case .support: "Support"
        }
    }

    var symbol: String {
        switch self {
        case .play: "play.fill"
        case .saves: "shield.lefthalf.filled"
        case .settings: "slider.horizontal.3"
        case .support: "waveform.path.ecg"
        }
    }
}

enum ComponentState: Equatable, Sendable {
    case ready(String? = nil)
    case missing(String? = nil)
    case working(String)
    case warning(String)
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var detail: String? {
        switch self {
        case .ready(let detail), .missing(let detail): detail
        case .working(let detail), .warning(let detail), .failed(let detail): detail
        }
    }
}

struct LauncherSnapshot: Equatable, Sendable {
    var host: ComponentState = .working("Checking this Mac")
    var runtime: ComponentState = .missing("Runtime not found")
    var bottle: ComponentState = .missing("Not created")
    var steam: ComponentState = .missing("Not installed")
    var game: ComponentState = .missing("Install through Steam")
    var saveCount = 0
    var backupCount = 0
    var freeDiskBytes: Int64 = 0
    var lowPowerModeEnabled = false
    var runtimePath: String?
    var bottlePath: String
    var gamePath: String?

    static func empty(paths: SecundaPaths) -> LauncherSnapshot {
        LauncherSnapshot(bottlePath: paths.bottleRoot.path)
    }
}

enum PrimaryAction: Equatable {
    case locateRuntime
    case createBottle
    case installSteam
    case openSteam
    case play
    case unavailable

    var title: String {
        switch self {
        case .locateRuntime: "Open Setup Help"
        case .createBottle: "Prepare Secunda"
        case .installSteam: "Install Steam"
        case .openSteam: "Open Steam"
        case .play: "Play Skyrim"
        case .unavailable: "Working…"
        }
    }

    var symbol: String {
        switch self {
        case .locateRuntime: "arrow.down.app.fill"
        case .createBottle: "sparkles"
        case .installSteam: "arrow.down.circle.fill"
        case .openSteam: "person.crop.circle"
        case .play: "play.fill"
        case .unavailable: "hourglass"
        }
    }
}

struct ActivityEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let message: String
    let kind: Kind

    enum Kind {
        case info
        case success
        case warning
        case error
    }
}

struct SetupProgress: Equatable, Sendable {
    let step: Int
    let totalSteps: Int
    let title: String
    let detail: String

    var fraction: Double {
        guard totalSteps > 0 else { return 0 }
        let completedSteps = min(max(step - 1, 0), totalSteps)
        return Double(completedSteps) / Double(totalSteps)
    }

    var stepLabel: String {
        "Step \(step) of \(totalSteps)"
    }
}

struct SetupJourney: Equatable, Sendable {
    let completedSteps: Int
    let totalSteps: Int
    let title: String
    let detail: String

    init(snapshot: LauncherSnapshot) {
        let states = [snapshot.runtime, snapshot.bottle, snapshot.steam, snapshot.game]
        completedSteps = states.prefix(while: \.isReady).count
        totalSteps = states.count

        switch completedSteps {
        case 0:
            title = "Secunda Engine"
            detail = "Checking the free, source-built engine included with Secunda."
        case 1:
            title = "Separate Windows Space"
            detail = "Next, create a separate managed place for Steam, Skyrim, and game settings."
        case 2:
            title = "Steam Client"
            detail = "Next, install Steam directly from Valve."
        case 3:
            title = "Finish in Steam"
            detail = "Sign in if asked, then install Skyrim Special Edition. Steam shows the download progress."
        default:
            title = "Ready to Launch"
            detail = "The required files are installed. Secunda applies its compatibility profile each time you press Play."
        }
    }

    var fraction: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(completedSteps) / Double(totalSteps)
    }

    var label: String {
        completedSteps == totalSteps ? "Setup complete" : "\(completedSteps) of \(totalSteps) ready"
    }
}

enum SkyrimLaunchStage: CaseIterable, Sendable {
    case checking
    case compatibility
    case profile
    case steam
    case game
}
