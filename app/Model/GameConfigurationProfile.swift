import Foundation

/// One value emitted into a game's command line. Keeping arguments as data
/// lets every title describe its syntax without title-specific launch code.
enum LaunchArgumentAtom: Equatable, Sendable {
    case literal(String)
    case width
    case height
    case fieldOfView
    case verticalSync(on: String, off: String)

    fileprivate func resolved(settings: GameSettings) -> String {
        switch self {
        case .literal(let value): value
        case .width: String(settings.width)
        case .height: String(settings.height)
        case .fieldOfView: String(settings.fieldOfView)
        case .verticalSync(let on, let off): settings.verticalSync ? on : off
        }
    }
}

struct DisplayArgumentTemplates: Equatable, Sendable {
    let borderless: [LaunchArgumentAtom]?
    let exclusive: [LaunchArgumentAtom]?
    let windowed: [LaunchArgumentAtom]?

    func template(for mode: DisplayMode) -> [LaunchArgumentAtom]? {
        switch mode {
        case .borderlessFullscreen: borderless
        case .exclusiveFullscreen: exclusive
        case .windowed: windowed
        }
    }

    var supportedModes: [DisplayMode] {
        DisplayMode.allCases.filter { template(for: $0) != nil }
    }
}

struct LaunchOptionChoice: Equatable, Sendable {
    let label: String
    let arguments: [String]
}

struct LaunchOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let caption: String
    let choices: [LaunchOptionChoice]
}

struct SteamRunningDirectLaunch: Equatable, Sendable {
    let arguments: [String]
    let steamReadyTimeoutSeconds: TimeInterval
}

enum ExclusiveFullscreenPolicy: Equatable, Sendable {
    case gameManaged
    case capturedHostMode
}

enum WineDisplayCoordinatePolicy: String, Equatable, Sendable {
    case inherited
    case backingPixels
}

struct GameLaunchProfile: Equatable, Sendable {
    let fixed: [LaunchArgumentAtom]
    let display: DisplayArgumentTemplates?
    let trailing: [LaunchArgumentAtom]
    let options: [LaunchOption]
    let steamRunningDirectLaunch: SteamRunningDirectLaunch?
    let dxmtConfigFragments: [String]
    let requiresVisibleWindow: Bool
    let exclusiveModeUsesGameDefault: Bool
    let exclusiveFullscreenPolicy: ExclusiveFullscreenPolicy
    /// Chooses the Win32 coordinate system for the entire Wine session.
    /// Backing-pixel profiles keep the player's exact resolution and rely on
    /// the host boundary for the one pixel-to-point conversion.
    let displayCoordinatePolicy: WineDisplayCoordinatePolicy
    /// Fullscreen-labelled modes must physically cover the selected display.
    /// This is a launch-health contract, independent of render resolution.
    let requiresFullDisplayCoverage: Bool
    /// Command-line -w/-h sessions render into the desktop the Mac driver
    /// exposes in screen points. Asking for a larger window than that
    /// desktop produces a black, unpresentable session, so opted-in games
    /// have their session resolution fitted to the desktop before launch.
    let fitsResolutionToDesktop: Bool
    /// Borderless windows use one host-derived client aspect that can scale
    /// uniformly in fullscreen and restore inside a decorated window.
    let usesTransitionSafeBorderlessSurface: Bool
    init(
        fixed: [LaunchArgumentAtom] = [],
        display: DisplayArgumentTemplates? = nil,
        trailing: [LaunchArgumentAtom] = [],
        options: [LaunchOption] = [],
        steamRunningDirectLaunch: SteamRunningDirectLaunch? = nil,
        dxmtConfigFragments: [String] = [],
        requiresVisibleWindow: Bool = false,
        exclusiveModeUsesGameDefault: Bool = false,
        exclusiveFullscreenPolicy: ExclusiveFullscreenPolicy = .gameManaged,
        displayCoordinatePolicy: WineDisplayCoordinatePolicy = .inherited,
        requiresFullDisplayCoverage: Bool = false,
        fitsResolutionToDesktop: Bool = false,
        usesTransitionSafeBorderlessSurface: Bool = false
    ) {
        self.fixed = fixed
        self.display = display
        self.trailing = trailing
        self.options = options
        self.steamRunningDirectLaunch = steamRunningDirectLaunch
        self.dxmtConfigFragments = dxmtConfigFragments
        self.requiresVisibleWindow = requiresVisibleWindow
        self.exclusiveModeUsesGameDefault = exclusiveModeUsesGameDefault
        self.exclusiveFullscreenPolicy = exclusiveFullscreenPolicy
        self.displayCoordinatePolicy = displayCoordinatePolicy
        self.requiresFullDisplayCoverage = requiresFullDisplayCoverage
        self.fitsResolutionToDesktop = fitsResolutionToDesktop
        self.usesTransitionSafeBorderlessSurface = usesTransitionSafeBorderlessSurface
    }

    func arguments(settings: GameSettings) -> [String] {
        var atoms = fixed
        if let display {
            let template = display.template(for: settings.displayMode)
                ?? display.template(for: display.supportedModes.first ?? .windowed)
                ?? []
            atoms += template
        }
        atoms += trailing
        var arguments = atoms.map { $0.resolved(settings: settings) }
        for option in options {
            guard let selected = settings.tuning[option.id],
                  let choice = option.choices.first(where: { $0.label == selected })
            else { continue }
            arguments += choice.arguments
        }
        return arguments
    }

    var managesResolution: Bool {
        let atoms = fixed + (display?.supportedModes.flatMap { display?.template(for: $0) ?? [] } ?? [])
        return atoms.contains(.width) && atoms.contains(.height)
    }

    var managesFieldOfView: Bool {
        (fixed + trailing).contains(.fieldOfView)
    }

    var managesVerticalSync: Bool {
        (fixed + trailing).contains {
            if case .verticalSync = $0 { return true }
            return false
        }
    }
}

/// A generated, live game configuration owned by the game. These targets are
/// never created; Secunda only replaces keys the game has already written
/// itself. Most profiles are sectioned INIs, while older Source branches keep
/// the same values in a quoted KeyValues object.
struct ManagedINIProfile: Equatable, Sendable {
    enum Format: Equatable, Sendable {
        case sectionedINI
        case quotedKeyValues
    }

    enum ValueSource: Equatable, Sendable {
        case width
        case height
        case fieldOfView
        case verticalSync(on: String, off: String)
        case fullscreen(on: String, off: String)
        case borderless(on: String, off: String)
    }

    struct Field: Equatable, Sendable {
        let key: String
        let source: ValueSource
    }

    let relativePath: String
    let section: String
    let fields: [Field]
    let includesQualityValues: Bool
    let format: Format

    init(
        relativePath: String,
        section: String,
        fields: [Field],
        includesQualityValues: Bool = false,
        format: Format = .sectionedINI
    ) {
        self.relativePath = relativePath
        self.section = section
        self.fields = fields
        self.includesQualityValues = includesQualityValues
        self.format = format
    }
}

struct ManagedDisplayCapabilities: Equatable, Sendable {
    let modes: [DisplayMode]
    let resolution: Bool
    let verticalSync: Bool
    let fieldOfView: Bool

    var hasAny: Bool {
        !modes.isEmpty || resolution || verticalSync || fieldOfView
    }
}

extension GameDescriptor {
    /// Lua prefs keys holding the game's device resolution as a quoted
    /// 'W,H[,rate]' string. The profile writer rewrites them to the fitted
    /// session resolution so the engine's own mode agrees with the window
    /// Secunda sizes; games without such a key manage resolution themselves.
    var luaPrefsAdapterKeyCandidates: [String] {
        switch id {
        case "supreme-commander", "forged-alliance":
            ["primary_adapter"]
        default:
            []
        }
    }

    /// These engines persist their window origin and cursor confinement in
    /// Lua. Secunda keeps them aligned with the selected display mode so the
    /// HUD and its mouse hit map share one coordinate space.
    var managesLuaDesktopWindow: Bool {
        switch id {
        case "supreme-commander", "forged-alliance": true
        default: false
        }
    }

    var launchProfile: GameLaunchProfile {
        switch id {
        case "skyrim-se":
            return GameLaunchProfile(
                exclusiveFullscreenPolicy: .capturedHostMode
            )
        case "insurgency":
            // Preserve real mode semantics. Borderless follows the desktop;
            // exclusive uses a physical mode; windowed keeps exact pixels.
            // The session boundary owns host pixel-to-point conversion.
            let resolution: [LaunchArgumentAtom] = [
                .literal("-w"), .width, .literal("-h"), .height
            ]
            return GameLaunchProfile(
                fixed: [.literal("-novid")],
                display: DisplayArgumentTemplates(
                    borderless: [.literal("-windowed"), .literal("-noborder")] + resolution,
                    exclusive: [.literal("-fullscreen")] + resolution,
                    windowed: [.literal("-windowed")] + resolution
                ),
                requiresVisibleWindow: true,
                exclusiveFullscreenPolicy: .capturedHostMode,
                displayCoordinatePolicy: .backingPixels,
                requiresFullDisplayCoverage: true
            )
        case "supcom2":
            // The engine exits before its own log initializes without this
            // windowed render-surface tuple. Borderless mode later upgrades
            // that surface through the Mac driver; windowed mode preserves
            // the player's requested client size.
            let window: [LaunchArgumentAtom] = [
                .literal("/windowed"), .width, .height
            ]
            return GameLaunchProfile(
                display: DisplayArgumentTemplates(
                    borderless: window,
                    exclusive: nil,
                    windowed: window
                )
            )
        case "supreme-commander", "forged-alliance":
            // Always /windowed: the engine's own exclusive mode negotiates a
            // display mode wined3d exposes in screen points, which cannot
            // express the Retina desktop. Borderless sessions instead take
            // the desktop size exactly (backing pixels under Retina mode) so
            // "fullscreen" fills the panel 1:1-sharp; a stored resolution
            // smaller than the desktop would otherwise open as a window in
            // the top-left corner sized in backing pixels.
            let window: [LaunchArgumentAtom] = [
                .literal("/windowed"), .width, .height
            ]
            return GameLaunchProfile(
                display: DisplayArgumentTemplates(
                    borderless: window,
                    exclusive: nil,
                    windowed: window
                ),
                fitsResolutionToDesktop: true
            )
        case "battlefront-2-classic":
            let resolution: [LaunchArgumentAtom] = [
                .literal("/resolution"), .width, .height
            ]
            return GameLaunchProfile(
                display: DisplayArgumentTemplates(
                    borderless: nil,
                    exclusive: resolution,
                    windowed: [.literal("/win")] + resolution
                ),
                options: [
                    LaunchOption(
                        id: "audio-buffer",
                        title: "Audio compatibility",
                        caption: "The 200 ms buffer is a publisher-documented fallback for broken or stuttering sound. Leave it at game default unless needed.",
                        choices: [
                            .init(label: QualityOption.gameDefaultLabel, arguments: []),
                            .init(label: "Compatibility (200 ms)", arguments: ["/audiomixbuffer", "200"])
                        ]
                    )
                ],
                exclusiveModeUsesGameDefault: true
            )
        case "angels-fall-first":
            return GameLaunchProfile(
                fixed: [.literal("-windowed")],
                steamRunningDirectLaunch: SteamRunningDirectLaunch(
                    arguments: ["-SEEKFREELOADING", "-DX9"],
                    steamReadyTimeoutSeconds: 30
                ),
                requiresVisibleWindow: true
            )
        default:
            return GameLaunchProfile()
        }
    }

    var managedINIProfiles: [ManagedINIProfile] {
        if id == "insurgency" {
            return [
                ManagedINIProfile(
                    relativePath: "insurgency/cfg/video.txt",
                    section: "config",
                    fields: [
                        .init(key: "setting.fullscreen", source: .fullscreen(on: "1", off: "0")),
                        .init(key: "setting.nowindowborder", source: .borderless(on: "1", off: "0")),
                        .init(key: "setting.defaultres", source: .width),
                        .init(key: "setting.defaultresheight", source: .height),
                        .init(key: "setting.mat_vsync", source: .verticalSync(on: "1", off: "0"))
                    ],
                    format: .quotedKeyValues
                )
            ]
        }
        return []
    }

    var steamRunningDirectLaunch: SteamRunningDirectLaunch? {
        launchProfile.steamRunningDirectLaunch
    }

    var gameProcessImageNames: [String] {
        if id == "insurgency" {
            return ["insurgency.exe", "insurgency_x64.exe"]
        }
        return [gameImageName]
    }

    var launcherProcessImageNames: [String] {
        guard !gameProcessImageNames.contains(where: {
            $0.caseInsensitiveCompare(launcherImageName) == .orderedSame
        }) else { return [] }
        return [launcherImageName]
    }

    var supportedDisplayModes: [DisplayMode] {
        if supportsDisplayProfile || managedINIProfiles.contains(where: { profile in
            profile.fields.contains {
                if case .fullscreen = $0.source { return true }
                if case .borderless = $0.source { return true }
                return false
            }
        }) {
            return DisplayMode.allCases
        }
        return launchProfile.display?.supportedModes ?? []
    }

    var managedDisplayCapabilities: ManagedDisplayCapabilities {
        let iniSources = managedINIProfiles.flatMap(\.fields).map(\.source)
        return ManagedDisplayCapabilities(
            modes: supportedDisplayModes,
            resolution: supportsDisplayProfile
                || launchProfile.managesResolution
                || iniSources.contains { if case .width = $0 { return true }; return false },
            verticalSync: supportsDisplayProfile
                || launchProfile.managesVerticalSync
                || iniSources.contains { if case .verticalSync = $0 { return true }; return false },
            fieldOfView: supportsDisplayProfile
                || launchProfile.managesFieldOfView
                || iniSources.contains { if case .fieldOfView = $0 { return true }; return false }
        )
    }

    var preferredInitialDisplayMode: DisplayMode {
        if id == "battlefront-2-classic" { return .windowed }
        return .borderlessFullscreen
    }

    var managedFieldOfViewRange: ClosedRange<Int> {
        id == "angels-fall-first" ? 75...105 : 70...110
    }

    /// Resolve the Steam install root from the executable path Steam already
    /// validated. Relative traversal is rejected before any profile lookup.
    func installationRoot(containing executable: URL) -> URL? {
        guard !executableRelativePath.hasPrefix("/") else { return nil }
        let components = executableRelativePath.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return nil }
        var root = executable.standardizedFileURL
        for _ in components { root.deleteLastPathComponent() }
        let rebuilt = components.reduce(root) { partial, component in
            partial.appendingPathComponent(component)
        }.standardizedFileURL
        return rebuilt.path == executable.standardizedFileURL.path ? root : nil
    }
}
