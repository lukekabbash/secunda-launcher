import Foundation

/// One optional add-on for a supported game. Detection is by file presence
/// inside the installed game directory; installation is always performed by
/// Steam itself for add-ons that have their own Steam app identifier.
struct DLCDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let steamAppID: String?
    let detectionFile: String
    let note: String?

    init(
        id: String,
        title: String,
        steamAppID: String? = nil,
        detectionFile: String,
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.steamAppID = steamAppID
        self.detectionFile = detectionFile
        self.note = note
    }
}

/// One selectable value for a quality option: a label plus the exact
/// [Display] ini keys it writes. An empty `values` map means "leave the
/// game's own setting untouched".
struct QualityChoice: Equatable, Sendable {
    let label: String
    let values: [String: String]
}

/// One curated graphics option a game exposes through Secunda. Only keys
/// the engine demonstrably honors belong here.
struct QualityOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let caption: String?
    let choices: [QualityChoice]

    init(id: String, title: String, caption: String? = nil, choices: [QualityChoice]) {
        self.id = id
        self.title = title
        self.caption = caption
        self.choices = choices
    }

    static let gameDefaultLabel = "Game default"

    /// Standard first entry: change nothing.
    static func gameDefault() -> QualityChoice {
        QualityChoice(label: gameDefaultLabel, values: [:])
    }
}

/// Direct3D 9 implementation choice for a game.
enum D3D9Backend: Equatable, Sendable {
    /// Wine's builtin translation over OpenGL — proven for light titles.
    case wined3d
    /// DXVK over MoltenVK/Metal — for heavier D3D9 games.
    case dxvk
}

/// One selectable value for a Lua-prefs tuning option.
struct LuaTuningChoice: Equatable, Sendable {
    let label: String
    let value: String
}

/// A numeric setting stored in a Lua-style prefs file (Supreme Commander 2's
/// Game.prefs). Secunda only rewrites keys it finds already present, so the
/// game must have created the file — and the key — first.
struct LuaTuningOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let caption: String?
    /// Key spellings to look for; the first one found in the file wins.
    let keyCandidates: [String]
    let choices: [LuaTuningChoice]

    init(
        id: String,
        title: String,
        caption: String? = nil,
        keyCandidates: [String],
        choices: [LuaTuningChoice]
    ) {
        self.id = id
        self.title = title
        self.caption = caption
        self.keyCandidates = keyCandidates
        self.choices = choices
    }
}

/// Single source of truth for per-game constants. Supporting another game
/// means adding a descriptor here and registering it in `supported`;
/// services read these fields instead of hardcoding one title.
struct GameDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let shortTitle: String
    let tagline: String
    let symbol: String
    let steamAppID: String
    let gameImageName: String
    let launcherImageName: String
    /// Path of the game binary inside the Steam install directory. Defaults
    /// to the image name; games like Supreme Commander 2 keep it in bin/.
    let executableRelativePath: String
    /// Path of the game's settings/saves folder under the Windows user's
    /// Documents directory (Bethesda uses My Games/, Gas Powered doesn't).
    let documentsRelativePath: String
    /// Lua-style prefs file, relative to the Windows user directory, for
    /// games configured that way instead of via INI (nil for Bethesda
    /// titles). Supreme Commander 2 keeps it under AppData\Local.
    let luaPrefsRelativePath: String?
    let luaTuningOptions: [LuaTuningOption]
    /// Which Direct3D 9 implementation the game launches with. DXMT owns
    /// D3D10/11 regardless; this only matters for D3D9-era titles.
    let d3d9Backend: D3D9Backend
    /// Bethesda-style prefs/custom ini names. Nil means the game has no
    /// Secunda-writable profile; display settings stay in the game itself.
    let prefsFileName: String?
    let customIniFileName: String?
    /// The [Display] key controlling vsync; Skyrim and Fallout 4 disagree.
    let vsyncKey: String
    let saveFileExtensions: [String]
    let defaultFieldOfView: Int
    /// File that proves the game data is really present (Steam manifests can
    /// claim completion before content lands). Nil skips the check.
    let baselineDataFile: String?
    let qualityOptions: [QualityOption]
    let dlc: [DLCDescriptor]
    /// Steam app whose artwork stands in when this one publishes none of
    /// its own (multi-component mode entries may borrow the base game's).
    var artworkFallbackAppID: String?
    /// Metal present cap applied through DXMT (`d3d11.preferredMaxFrameRate`).
    /// Fallout 4's camera/Havok sampling breaks above 60; leave nil to uncapped.
    let preferredMaxFrameRate: Int?
    /// Extra Custom.ini keys keyed by section name (e.g. "Controls").
    let customIniValues: [String: [String: String]]
    /// Force session LogPixels to 96 so DPI-unaware look deltas map 1:1.
    /// Steam keeps the bottle's Retina DPI between sessions.
    let prefersNativeSessionDPI: Bool
    /// The game needs an undecorated, screen-covering borderless surface when
    /// its own display settings cannot express that mode through an INI.
    let usesScreenCoveringBorderlessSurface: Bool
    /// Write aspect-correct fMouseHeadingX/YScale so vertical look isn't sticky.
    let appliesAspectCorrectMouseLook: Bool
    /// Whether this title needs Secunda's redistributable XAudio/WMA voice
    /// path. Keeping this explicit prevents a 64-bit fix from being applied
    /// silently to unrelated or 32-bit games.
    let usesNativeVoiceAudioFix: Bool

    var supportsDisplayProfile: Bool { prefsFileName != nil }

    /// Host-side process controls include the installed entry point even
    /// when launch health deliberately follows a different final process.
    var processImageNames: [String] {
        var names = gameProcessImageNames + [launcherImageName]
        names.append(URL(fileURLWithPath: executableRelativePath).lastPathComponent)
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Metal owns the frame cap — the game's own vsync interval would only
    /// add present latency on top.
    var usesMetalFramePacing: Bool {
        preferredMaxFrameRate != nil
    }

    func qualityOption(for id: String) -> QualityOption? {
        qualityOptions.first { $0.id == id }
    }

    /// Shared Creation Engine options valid in both Skyrim SE and Fallout 4.
    /// A title may expose the zero-distance shadow workaround without adding
    /// it to every game that happens to use the same profile format.
    private static func creationEngineOptions(
        includesShadowOffCompatibility: Bool = false
    ) -> [QualityOption] {
        var shadowDistanceChoices: [QualityChoice] = [
            .init(label: QualityOption.gameDefaultLabel, values: [:])
        ]
        if includesShadowOffCompatibility {
            shadowDistanceChoices.append(
                .init(label: "Off (compatibility)", values: ["fShadowDistance": "0.0000"])
            )
        }
        shadowDistanceChoices += [
            .init(label: "Short", values: ["fShadowDistance": "2500.0000"]),
            .init(label: "Medium", values: ["fShadowDistance": "4000.0000"]),
            .init(label: "Long", values: ["fShadowDistance": "8000.0000"])
        ]

        return [
            QualityOption(
                id: "ssao",
                title: "Ambient occlusion",
                caption: "Contact shading in corners and under objects. Off is a solid frame-rate win.",
                choices: [
                    .init(label: QualityOption.gameDefaultLabel, values: [:]),
                    .init(label: "Off", values: ["bSAOEnable": "0"]),
                    .init(label: "On", values: ["bSAOEnable": "1"])
                ]
            ),
            QualityOption(
                id: "shadow-resolution",
                title: "Shadow resolution",
                caption: "Sharper shadows cost GPU time; 2048 is a good middle ground.",
                choices: [
                    .init(label: QualityOption.gameDefaultLabel, values: [:]),
                    .init(label: "1024", values: ["iShadowMapResolution": "1024"]),
                    .init(label: "2048", values: ["iShadowMapResolution": "2048"]),
                    .init(label: "4096", values: ["iShadowMapResolution": "4096"])
                ]
            ),
            QualityOption(
                id: "shadow-distance",
                title: "Shadow distance",
                caption: includesShadowOffCompatibility
                    ? "How far away the world casts shadows. Compatibility mode prevents camera-following dark patches by disabling exterior shadows."
                    : "How far away the world still casts shadows.",
                choices: shadowDistanceChoices
            ),
            QualityOption(
                id: "anisotropy",
                title: "Anisotropic filtering",
                caption: "Keeps ground textures sharp at glancing angles. Cheap on Apple GPUs; 16x is fine.",
                choices: [
                    .init(label: QualityOption.gameDefaultLabel, values: [:]),
                    .init(label: "Off", values: ["iMaxAnisotropy": "0"]),
                    .init(label: "8x", values: ["iMaxAnisotropy": "8"]),
                    .init(label: "16x", values: ["iMaxAnisotropy": "16"])
                ]
            ),
            QualityOption(
                id: "lens-flare",
                title: "Lens flare",
                choices: [
                    .init(label: QualityOption.gameDefaultLabel, values: [:]),
                    .init(label: "Off", values: ["bLensFlare": "0"]),
                    .init(label: "On", values: ["bLensFlare": "1"])
                ]
            ),
            QualityOption(
                id: "grass-distance",
                title: "Grass draw distance",
                caption: "Closer fade means fewer grass batches on screen.",
                choices: [
                    .init(label: QualityOption.gameDefaultLabel, values: [:]),
                    .init(label: "Near", values: ["fGrassStartFadeDistance": "3500.0000"]),
                    .init(label: "Medium", values: ["fGrassStartFadeDistance": "7000.0000"]),
                    .init(label: "Far", values: ["fGrassStartFadeDistance": "14000.0000"])
                ]
            )
        ]
    }

    /// Steam's own artwork CDN. Fetched at runtime for the player's library
    /// presentation and never redistributed inside Secunda.
    ///
    /// Candidates are tried in order. Some mode-specific entries publish
    /// only a wide header image, so the chain ends at the base app's artwork.
    var cardArtworkCandidates: [URL] {
        artworkURLs(
            paths: ["library_600x900.jpg", "header.jpg"],
            fallbackPaths: ["library_600x900.jpg", "header.jpg"]
        )
    }

    var heroArtworkCandidates: [URL] {
        artworkURLs(
            paths: ["library_hero.jpg", "header.jpg"],
            fallbackPaths: ["library_hero.jpg", "header.jpg"]
        )
    }

    private func artworkURLs(paths: [String], fallbackPaths: [String]) -> [URL] {
        var urls = paths.compactMap {
            URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(steamAppID)/\($0)")
        }
        if let fallbackAppID = artworkFallbackAppID {
            urls += fallbackPaths.compactMap {
                URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(fallbackAppID)/\($0)")
            }
        }
        return urls
    }

    static let skyrimSE = GameDescriptor(
        id: "skyrim-se",
        title: "The Elder Scrolls V: Skyrim Special Edition",
        shortTitle: "Skyrim",
        tagline: "Dragons, shouts, and a province that never lets go.",
        symbol: "mountain.2.fill",
        steamAppID: "489830",
        gameImageName: "SkyrimSE.exe",
        launcherImageName: "SkyrimSELauncher.exe",
        executableRelativePath: "SkyrimSE.exe",
        documentsRelativePath: "My Games/Skyrim Special Edition",
        luaPrefsRelativePath: nil,
        luaTuningOptions: [],
        d3d9Backend: .wined3d,
        prefsFileName: "SkyrimPrefs.ini",
        customIniFileName: "SkyrimCustom.ini",
        vsyncKey: "iVSyncPresentInterval",
        saveFileExtensions: ["ess"],
        defaultFieldOfView: 80,
        baselineDataFile: "Data/Skyrim.esm",
        qualityOptions: creationEngineOptions(includesShadowOffCompatibility: true) + [
            QualityOption(
                id: "godrays",
                title: "God rays",
                caption: "Volumetric sunlight. A large frame-rate cost on this engine; Off is recommended.",
                choices: [
                    .init(label: QualityOption.gameDefaultLabel, values: [:]),
                    .init(label: "Off", values: ["bVolumetricLightingEnable": "0"]),
                    .init(label: "On", values: ["bVolumetricLightingEnable": "1"])
                ]
            ),
            QualityOption(
                id: "taa",
                title: "Anti-aliasing (TAA)",
                caption: "Temporal anti-aliasing smooths edges with slight softening.",
                choices: [
                    .init(label: QualityOption.gameDefaultLabel, values: [:]),
                    .init(label: "Off", values: ["bUseTAA": "0"]),
                    .init(label: "On", values: ["bUseTAA": "1"])
                ]
            )
        ],
        dlc: [
            DLCDescriptor(
                id: "skyrim-dawnguard",
                title: "Dawnguard",
                detectionFile: "Data/Dawnguard.esm",
                note: "Included with Special Edition."
            ),
            DLCDescriptor(
                id: "skyrim-hearthfire",
                title: "Hearthfire",
                detectionFile: "Data/HearthFires.esm",
                note: "Included with Special Edition."
            ),
            DLCDescriptor(
                id: "skyrim-dragonborn",
                title: "Dragonborn",
                detectionFile: "Data/Dragonborn.esm",
                note: "Included with Special Edition."
            ),
            DLCDescriptor(
                id: "skyrim-anniversary",
                title: "Anniversary Upgrade",
                steamAppID: "1746860",
                detectionFile: "Data/ccBGSSSE001-Fish.esm",
                note: "Paid upgrade adding all Creation Club content."
            )
        ],
        preferredMaxFrameRate: nil,
        customIniValues: [:],
        // Creation Engine's borderless mode needs the same point-space,
        // screen-covering Mac surface as Fallout 4 or the fixed HUD can sit
        // below the menu bar on a Retina display.
        prefersNativeSessionDPI: true,
        usesScreenCoveringBorderlessSurface: true,
        appliesAspectCorrectMouseLook: false,
        usesNativeVoiceAudioFix: true
    )

    static let fallout4 = GameDescriptor(
        id: "fallout-4",
        title: "Fallout 4",
        shortTitle: "Fallout 4",
        tagline: "War never changes. The Commonwealth is waiting.",
        symbol: "atom",
        steamAppID: "377160",
        gameImageName: "Fallout4.exe",
        launcherImageName: "Fallout4Launcher.exe",
        executableRelativePath: "Fallout4.exe",
        documentsRelativePath: "My Games/Fallout4",
        luaPrefsRelativePath: nil,
        luaTuningOptions: [],
        d3d9Backend: .wined3d,
        prefsFileName: "Fallout4Prefs.ini",
        customIniFileName: "Fallout4Custom.ini",
        vsyncKey: "iPresentInterval",
        saveFileExtensions: ["fos"],
        defaultFieldOfView: 80,
        baselineDataFile: "Data/Fallout4.esm",
        qualityOptions: creationEngineOptions() + [
            QualityOption(
                id: "godrays",
                title: "God rays",
                caption: "Volumetric sunlight is one of Fallout 4's heaviest effects. Off is strongly recommended on this runtime.",
                choices: [
                    .init(label: QualityOption.gameDefaultLabel, values: [:]),
                    .init(label: "Off", values: ["bVolumetricLightingEnable": "0"]),
                    .init(label: "Low", values: [
                        "bVolumetricLightingEnable": "1",
                        "iVolumetricLightingQuality": "0"
                    ]),
                    .init(label: "Medium", values: [
                        "bVolumetricLightingEnable": "1",
                        "iVolumetricLightingQuality": "1"
                    ]),
                    .init(label: "High", values: [
                        "bVolumetricLightingEnable": "1",
                        "iVolumetricLightingQuality": "2"
                    ])
                ]
            ),
            QualityOption(
                id: "ssr",
                title: "Screen-space reflections",
                caption: "Wet-surface reflections. Off saves GPU time in the Commonwealth's many puddles.",
                choices: [
                    .init(label: QualityOption.gameDefaultLabel, values: [:]),
                    .init(label: "Off", values: ["bScreenSpaceReflections": "0"]),
                    .init(label: "On", values: ["bScreenSpaceReflections": "1"])
                ]
            ),
            QualityOption(
                id: "depth-of-field",
                title: "Depth of field",
                caption: "Background blur in dialogue and aiming.",
                choices: [
                    .init(label: QualityOption.gameDefaultLabel, values: [:]),
                    .init(label: "Off", values: ["bDoDepthOfField": "0"]),
                    .init(label: "On", values: ["bDoDepthOfField": "1"])
                ]
            )
        ],
        dlc: [
            DLCDescriptor(
                id: "fallout4-automatron",
                title: "Automatron",
                steamAppID: "435880",
                detectionFile: "Data/DLCRobot.esm"
            ),
            DLCDescriptor(
                id: "fallout4-wasteland-workshop",
                title: "Wasteland Workshop",
                steamAppID: "435881",
                detectionFile: "Data/DLCworkshop01.esm"
            ),
            DLCDescriptor(
                id: "fallout4-far-harbor",
                title: "Far Harbor",
                steamAppID: "435870",
                detectionFile: "Data/DLCCoast.esm"
            ),
            DLCDescriptor(
                id: "fallout4-contraptions",
                title: "Contraptions Workshop",
                steamAppID: "480630",
                detectionFile: "Data/DLCworkshop02.esm"
            ),
            DLCDescriptor(
                id: "fallout4-vault-tec",
                title: "Vault-Tec Workshop",
                steamAppID: "480631",
                detectionFile: "Data/DLCworkshop03.esm"
            ),
            DLCDescriptor(
                id: "fallout4-nuka-world",
                title: "Nuka-World",
                steamAppID: "490650",
                detectionFile: "Data/DLCNukaWorld.esm"
            ),
            DLCDescriptor(
                id: "fallout4-hd-textures",
                title: "High Resolution Texture Pack",
                steamAppID: "540810",
                detectionFile: "Data/DLCUltraHighResolution - Textures01.ba2",
                note: "Free but ~58 GB and heavy on the GPU. Not recommended on this runtime."
            )
        ],
        // Creation Engine samples look input inside the Havok tick. Above 60
        // fps that math jitters the camera; DXMT's Metal present cap keeps
        // the game honest without changing the Mac display refresh rate.
        preferredMaxFrameRate: 60,
        customIniValues: [
            "Controls": [
                "bMouseAcceleration": "0",
                // CodeWeavers tip: keep relative mouse deltas while unfocused
                // borderless windows fight the Mac pointer.
                "bBackgroundMouse": "1"
            ]
        ],
        // Retina LogPixels=216 quantizes small look deltas into sticky steps.
        prefersNativeSessionDPI: true,
        usesScreenCoveringBorderlessSurface: true,
        appliesAspectCorrectMouseLook: true,
        usesNativeVoiceAudioFix: true
    )

    static let supcom2 = GameDescriptor(
        id: "supcom2",
        title: "Supreme Commander 2",
        shortTitle: "Supreme Commander 2",
        tagline: "Thousand-unit armies, one supreme commander.",
        symbol: "flag.2.crossed.fill",
        steamAppID: "40100",
        gameImageName: "SupremeCommander2.exe",
        launcherImageName: "SupremeCommander2.exe",
        executableRelativePath: "bin/SupremeCommander2.exe",
        documentsRelativePath: "My Games/Gas Powered Games/Supreme Commander 2",
        luaPrefsRelativePath: "AppData/Local/Gas Powered Games/Supreme Commander 2/Game.prefs",
        luaTuningOptions: [
            LuaTuningOption(
                id: "unit-cap",
                title: "Unit cap",
                caption: "Maximum army size. The game records this after you host one skirmish; until then Secunda leaves it alone.",
                keyCandidates: ["UnitCap", "unit_cap", "unitCap"],
                choices: [
                    .init(label: QualityOption.gameDefaultLabel, value: ""),
                    .init(label: "250", value: "250"),
                    .init(label: "500", value: "500"),
                    .init(label: "750", value: "750"),
                    .init(label: "1000", value: "1000")
                ]
            )
        ],
        d3d9Backend: .wined3d,
        prefsFileName: nil,
        customIniFileName: nil,
        vsyncKey: "iPresentInterval",
        saveFileExtensions: [],
        defaultFieldOfView: 90,
        baselineDataFile: nil,
        qualityOptions: [],
        dlc: [],
        preferredMaxFrameRate: nil,
        customIniValues: [:],
        // Match Fallout's point-space fullscreen contract. The engine still
        // needs /windowed W H to initialize, while the Mac driver supplies the
        // undecorated screen-covering surface around that render target.
        prefersNativeSessionDPI: true,
        usesScreenCoveringBorderlessSurface: true,
        appliesAspectCorrectMouseLook: false,
        usesNativeVoiceAudioFix: false
    )

    private static func blackOps2(
        id: String,
        title: String,
        shortTitle: String,
        tagline: String,
        symbol: String,
        steamAppID: String,
        executable: String
    ) -> GameDescriptor {
        GameDescriptor(
            id: id,
            title: title,
            shortTitle: shortTitle,
            tagline: tagline,
            symbol: symbol,
            steamAppID: steamAppID,
            gameImageName: executable,
            launcherImageName: executable,
            executableRelativePath: executable,
            documentsRelativePath: "My Games/Call of Duty Black Ops II",
            luaPrefsRelativePath: nil,
            luaTuningOptions: [],
            // The title's normal renderer is PE32 Direct3D 11 through the
            // runtime bridge. This field only chooses the conservative
            // builtin fallback if setup requests Direct3D 9.
            d3d9Backend: .wined3d,
            prefsFileName: nil,
            customIniFileName: nil,
            vsyncKey: "iPresentInterval",
            saveFileExtensions: [],
            defaultFieldOfView: 80,
            baselineDataFile: nil,
            qualityOptions: [],
            dlc: [],
            artworkFallbackAppID: "202970",
            preferredMaxFrameRate: nil,
            customIniValues: [:],
            prefersNativeSessionDPI: false,
            usesScreenCoveringBorderlessSurface: false,
            appliesAspectCorrectMouseLook: false,
            usesNativeVoiceAudioFix: false
        )
    }

    static let blackOps2SP = blackOps2(
        id: "bo2-campaign",
        title: "Call of Duty: Black Ops II",
        shortTitle: "Black Ops II",
        tagline: "The future is black. Campaign.",
        symbol: "scope",
        steamAppID: "202970",
        executable: "t6sp.exe"
    )

    static let blackOps2MP = blackOps2(
        id: "bo2-multiplayer",
        title: "Call of Duty: Black Ops II - Multiplayer",
        shortTitle: "BO2 Multiplayer",
        tagline: "Pick ten. Prestige forever.",
        symbol: "person.3.fill",
        steamAppID: "202990",
        executable: "t6mp.exe"
    )

    static let blackOps2Zombies = blackOps2(
        id: "bo2-zombies",
        title: "Call of Duty: Black Ops II - Zombies",
        shortTitle: "BO2 Zombies",
        tagline: "They keep coming. Tranzit awaits.",
        symbol: "figure.walk.motion",
        steamAppID: "212910",
        executable: "t6zm.exe"
    )

    static let supported: [GameDescriptor] = [
        .skyrimSE,
        .fallout4,
        .supremeCommander,
        .forgedAlliance,
        .supcom2,
        .battlefront2Classic,
        .insurgency,
        .angelsFallFirst,
        .blackOps2SP,
        .blackOps2MP,
        .blackOps2Zombies
    ]

}

/// One library surface entry. Most groups wrap a single game; multi-component
/// titles group their Steam components behind one card with mode selection.
struct GameGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let shortTitle: String
    let symbol: String
    let componentIDs: [String]

    var isMultiComponent: Bool { componentIDs.count > 1 }

    var components: [GameDescriptor] {
        componentIDs.compactMap { GameDescriptor.descriptor(for: $0) }
    }

    /// The component whose cover art represents the whole group. Fixed, so
    /// the library card and sidebar icon never change when the player
    /// switches modes or default launch targets.
    var artworkComponent: GameDescriptor? {
        components.first
    }

    static let all: [GameGroup] = [
        GameGroup(
            id: "skyrim-se",
            title: GameDescriptor.skyrimSE.title,
            shortTitle: GameDescriptor.skyrimSE.shortTitle,
            symbol: GameDescriptor.skyrimSE.symbol,
            componentIDs: ["skyrim-se"]
        ),
        GameGroup(
            id: "fallout-4",
            title: GameDescriptor.fallout4.title,
            shortTitle: GameDescriptor.fallout4.shortTitle,
            symbol: GameDescriptor.fallout4.symbol,
            componentIDs: ["fallout-4"]
        ),
        GameGroup(
            id: "supreme-commander",
            title: "Supreme Commander",
            shortTitle: "Supreme Commander",
            symbol: "flag.2.crossed.fill",
            componentIDs: ["supreme-commander", "forged-alliance"]
        ),
        GameGroup(
            id: "supcom2",
            title: GameDescriptor.supcom2.title,
            shortTitle: GameDescriptor.supcom2.shortTitle,
            symbol: GameDescriptor.supcom2.symbol,
            componentIDs: ["supcom2"]
        ),
        GameGroup(
            id: "battlefront-2-classic",
            title: GameDescriptor.battlefront2Classic.title,
            shortTitle: GameDescriptor.battlefront2Classic.shortTitle,
            symbol: GameDescriptor.battlefront2Classic.symbol,
            componentIDs: ["battlefront-2-classic"]
        ),
        GameGroup(
            id: "insurgency",
            title: GameDescriptor.insurgency.title,
            shortTitle: GameDescriptor.insurgency.shortTitle,
            symbol: GameDescriptor.insurgency.symbol,
            componentIDs: ["insurgency"]
        ),
        GameGroup(
            id: "angels-fall-first",
            title: GameDescriptor.angelsFallFirst.title,
            shortTitle: GameDescriptor.angelsFallFirst.shortTitle,
            symbol: GameDescriptor.angelsFallFirst.symbol,
            componentIDs: ["angels-fall-first"]
        ),
        GameGroup(
            id: "black-ops-2",
            title: "Call of Duty: Black Ops II",
            shortTitle: "Black Ops II",
            symbol: "scope",
            componentIDs: ["bo2-campaign", "bo2-multiplayer", "bo2-zombies"]
        )
    ]

    static func group(for id: String) -> GameGroup? {
        all.first { $0.id == id }
    }

    /// The group a descriptor belongs to.
    static func group(containing descriptorID: String) -> GameGroup? {
        all.first { $0.componentIDs.contains(descriptorID) }
    }
}

extension GameDescriptor {
    /// Mode label inside a multi-component group (e.g. "Campaign").
    var modeTitle: String {
        switch id {
        case "supreme-commander": "Original"
        case "forged-alliance": "Forged Alliance"
        case "bo2-campaign": "Campaign"
        case "bo2-multiplayer": "Multiplayer"
        case "bo2-zombies": "Zombies"
        default: shortTitle
        }
    }

    static func descriptor(for id: String) -> GameDescriptor? {
        supported.first { $0.id == id }
    }
}
