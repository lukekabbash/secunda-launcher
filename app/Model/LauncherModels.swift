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
    var runtime: ComponentState = .missing("Runtime not found")
    var bottle: ComponentState = .missing("Not created")
    var steam: ComponentState = .missing("Not installed")
    var game: ComponentState = .missing("Install through Steam")
    var saveCount = 0
    var backupCount = 0
    var freeDiskBytes: Int64 = 0
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
        case .locateRuntime: "Repair Runtime"
        case .createBottle: "Prepare Secunda"
        case .installSteam: "Install Steam"
        case .openSteam: "Open Steam"
        case .play: "Play Skyrim"
        case .unavailable: "Working…"
        }
    }

    var symbol: String {
        switch self {
        case .locateRuntime: "wrench.and.screwdriver"
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
        return Double(min(max(step, 0), totalSteps)) / Double(totalSteps)
    }

    var stepLabel: String {
        "Step \(step) of \(totalSteps)"
    }
}
