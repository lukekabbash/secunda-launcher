import Foundation

enum AppVersion {
    static var marketing: String {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let bundled, !bundled.isEmpty else { return "0.1.0" }
        return bundled
    }

    static var label: String { "v\(marketing)" }
}

/// Sidebar navigation. The library card grid is the home surface; each
/// supported game gets its own entry; launcher settings (which include
/// support and recovery) live behind the gear at the sidebar's foot.
enum SidebarItem: Hashable, Identifiable {
    case games
    case game(String)
    case settings

    var id: String {
        switch self {
        case .games: "games"
        case .game(let gameID): "game-\(gameID)"
        case .settings: "settings"
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

/// Per-game portion of the launcher snapshot. Until a probe has actually
/// run, the state is "checking" — the UI must never claim "not installed"
/// before confirming it.
struct GameSnapshot: Equatable, Sendable {
    var state: ComponentState = .working("Checking")
    var path: String?
    var saveCount = 0
    var backupCount = 0
}

struct LauncherSnapshot: Equatable, Sendable {
    var host: ComponentState = .working("Checking this Mac")
    var runtime: ComponentState = .missing("Runtime not found")
    var bottle: ComponentState = .missing("Not prepared")
    var steam: ComponentState = .missing("Not installed")
    var games: [String: GameSnapshot] = [:]
    var freeDiskBytes: Int64 = 0
    var lowPowerModeEnabled = false
    var runtimePath: String?
    var bottlePath: String

    func game(_ descriptor: GameDescriptor) -> GameSnapshot {
        games[descriptor.id] ?? GameSnapshot()
    }

    static func empty(paths: SecundaPaths) -> LauncherSnapshot {
        LauncherSnapshot(bottlePath: paths.bottleRoot.path)
    }
}

enum PrimaryAction: Equatable {
    case locateRuntime
    case createBottle
    case installSteam
    case installGame
    case play
    case unavailable

    func title(for descriptor: GameDescriptor) -> String {
        switch self {
        case .locateRuntime: "Open Settings"
        case .createBottle: "Prepare Secunda"
        case .installSteam: "Install Steam"
        case .installGame: "Install \(descriptor.shortTitle)"
        case .play: "Play \(descriptor.shortTitle)"
        case .unavailable: "Working…"
        }
    }

    var symbol: String {
        switch self {
        case .locateRuntime: "arrow.down.app.fill"
        case .createBottle: "sparkles"
        case .installSteam: "arrow.down.circle.fill"
        case .installGame: "arrow.down.circle.fill"
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

    init(snapshot: LauncherSnapshot, descriptor: GameDescriptor) {
        let states = [
            snapshot.runtime,
            snapshot.bottle,
            snapshot.steam,
            snapshot.game(descriptor).state
        ]
        completedSteps = states.prefix(while: \.isReady).count
        totalSteps = states.count

        switch completedSteps {
        case 0:
            title = "Compatibility Runtime"
            detail = "Checking the compatibility runtime included with this copy of Secunda."
        case 1:
            title = "Game Space"
            detail = "Next, create the private Windows environment Secunda uses for Steam, your games, and their settings."
        case 2:
            title = "Steam Client"
            detail = "Next, install Steam directly from Valve."
        case 3:
            title = "Finish in Steam"
            detail = "Sign in if asked, then install \(descriptor.shortTitle). Steam shows the download progress."
        default:
            title = "Ready to Launch"
            detail = "The required files are installed. Secunda applies this title’s launch settings each time you press Play."
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
