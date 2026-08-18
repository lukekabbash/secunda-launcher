import Foundation

enum InstallSpacePolicy {
    static let reserveBytes: Int64 = 25 * 1_024 * 1_024 * 1_024

    static func requiredFreeBytes(
        for descriptor: GameDescriptor,
        pending: [GameDescriptor]
    ) -> Int64? {
        guard let targetBytes = descriptor.estimatedInstallBytes else { return nil }
        let pendingBytes = pending
            .filter { $0.id != descriptor.id }
            .compactMap(\.estimatedInstallBytes)
            .reduce(0, +)
        return reserveBytes + targetBytes + pendingBytes
    }
}

/// Curated profiles for compact, established Windows titles. Each profile
/// contains only launch and detection behavior Secunda can verify directly.
extension GameDescriptor {
    var estimatedInstallBytes: Int64? {
        let gib: Int64 = 1_024 * 1_024 * 1_024
        return switch id {
        case "insurgency": Int64(Double(gib) * 8.48)
        case "supreme-commander": Int64(Double(gib) * 7.25)
        case "forged-alliance": Int64(Double(gib) * 7.88)
        case "angels-fall-first": Int64(Double(gib) * 5.65)
        case "battlefront-2-classic": Int64(Double(gib) * 9.59)
        default: nil
        }
    }

    static let insurgency = GameDescriptor(
        id: "insurgency",
        title: "Insurgency",
        shortTitle: "Insurgency",
        tagline: "Runs on Apple silicon.",
        symbol: "scope",
        steamAppID: "222880",
        gameImageName: "insurgency.exe",
        // Both current binaries are final game processes, not launchers.
        launcherImageName: "insurgency.exe",
        executableRelativePath: "insurgency.exe",
        documentsRelativePath: "",
        luaPrefsRelativePath: nil,
        luaTuningOptions: [],
        // The shipped default branch is 32-bit and cannot reach Vulkan from
        // WoW64 in this runtime. Declare the builtin backend it actually loads.
        d3d9Backend: .wined3d,
        prefsFileName: nil,
        customIniFileName: nil,
        vsyncKey: "mat_vsync",
        saveFileExtensions: [],
        defaultFieldOfView: 90,
        baselineDataFile: "insurgency/insurgency_materials_000.vpk",
        qualityOptions: [],
        dlc: [],
        preferredMaxFrameRate: nil,
        customIniValues: [:],
        // Keep native DPI for unscaled input while the launch profile owns
        // the backing-pixel coordinate contract and real per-mode geometry.
        prefersNativeSessionDPI: true,
        usesScreenCoveringBorderlessSurface: false,
        appliesAspectCorrectMouseLook: false,
        usesNativeVoiceAudioFix: false
    )

    static let supremeCommander = supremeCommanderProfile(
        id: "supreme-commander",
        title: "Supreme Commander",
        shortTitle: "Supreme Commander",
        tagline: "Untested.",
        steamAppID: "9350",
        executable: "SupremeCommander.exe",
        installExecutable: "bin/SupremeCommander.exe",
        profileDirectory: "SupremeCommander",
        documentsDirectory: ""
    )

    static let forgedAlliance = supremeCommanderProfile(
        id: "forged-alliance",
        title: "Supreme Commander: Forged Alliance",
        shortTitle: "Forged Alliance",
        tagline: "Untested.",
        steamAppID: "9420",
        executable: "SupremeCommander.exe",
        installExecutable: "bin/SupremeCommander.exe",
        profileDirectory: "Supreme Commander Forged Alliance",
        documentsDirectory: "My Games/Gas Powered Games/Supreme Commander Forged Alliance"
    )

    static let angelsFallFirst = GameDescriptor(
        id: "angels-fall-first",
        title: "Angels Fall First",
        shortTitle: "Angels Fall First",
        tagline: "Untested.",
        symbol: "airplane",
        steamAppID: "367270",
        gameImageName: "AFFGame.exe",
        launcherImageName: "AFFLift.exe",
        executableRelativePath: "Binaries/Win64/AFFGame.exe",
        documentsRelativePath: "",
        luaPrefsRelativePath: nil,
        luaTuningOptions: [],
        d3d9Backend: .dxvk,
        prefsFileName: nil,
        customIniFileName: nil,
        vsyncKey: "UseVsync",
        saveFileExtensions: [],
        defaultFieldOfView: 90,
        baselineDataFile: "AFFGame/CookedPC/AFFGame.u",
        qualityOptions: [],
        dlc: [],
        preferredMaxFrameRate: nil,
        customIniValues: [:],
        prefersNativeSessionDPI: false,
        usesScreenCoveringBorderlessSurface: false,
        appliesAspectCorrectMouseLook: false,
        usesNativeVoiceAudioFix: false
    )

    static let battlefront2Classic = GameDescriptor(
        id: "battlefront-2-classic",
        title: "STAR WARS Battlefront II (Classic, 2005)",
        shortTitle: "Battlefront II Classic",
        tagline: "Untested.",
        symbol: "star.fill",
        steamAppID: "6060",
        gameImageName: "BattlefrontII.exe",
        launcherImageName: "BattlefrontII.exe",
        executableRelativePath: "GameData/BattlefrontII.exe",
        documentsRelativePath: "",
        luaPrefsRelativePath: nil,
        luaTuningOptions: [],
        d3d9Backend: .wined3d,
        prefsFileName: nil,
        customIniFileName: nil,
        vsyncKey: "",
        saveFileExtensions: [],
        defaultFieldOfView: 75,
        baselineDataFile: "GameData/data/_lvl_pc/common.lvl",
        qualityOptions: [],
        dlc: [],
        preferredMaxFrameRate: nil,
        customIniValues: [:],
        prefersNativeSessionDPI: false,
        usesScreenCoveringBorderlessSurface: false,
        appliesAspectCorrectMouseLook: false,
        usesNativeVoiceAudioFix: false
    )

    private static func supremeCommanderProfile(
        id: String,
        title: String,
        shortTitle: String,
        tagline: String,
        steamAppID: String,
        executable: String,
        installExecutable: String,
        profileDirectory: String,
        documentsDirectory: String
    ) -> GameDescriptor {
        GameDescriptor(
            id: id,
            title: title,
            shortTitle: shortTitle,
            tagline: tagline,
            symbol: "flag.2.crossed.fill",
            steamAppID: steamAppID,
            gameImageName: executable,
            launcherImageName: executable,
            executableRelativePath: installExecutable,
            documentsRelativePath: documentsDirectory,
            luaPrefsRelativePath: "AppData/Local/Gas Powered Games/\(profileDirectory)/Game.prefs",
            luaTuningOptions: supremeCommanderTuningOptions,
            d3d9Backend: .wined3d,
            prefsFileName: nil,
            customIniFileName: nil,
            vsyncKey: "vsync",
            saveFileExtensions: [],
            defaultFieldOfView: 90,
            baselineDataFile: "gamedata/lua.scd",
            qualityOptions: [],
            dlc: [],
            preferredMaxFrameRate: nil,
            customIniValues: [:],
            // Point-space session: /windowed at the point desktop fills the
            // panel with the engine's fixed-pixel UI at its intended size.
            // A Retina-backing session either quarters the window (small
            // stored sizes) or shrinks the UI to half scale (native sizes).
            prefersNativeSessionDPI: true,
            usesScreenCoveringBorderlessSurface: false,
            appliesAspectCorrectMouseLook: false,
            usesNativeVoiceAudioFix: false
        )
    }

    private static let supremeCommanderTuningOptions: [LuaTuningOption] = [
        LuaTuningOption(
            id: "fidelity",
            title: "Graphics fidelity",
            caption: "Model, lighting, and effect complexity.",
            keyCandidates: ["fidelity"],
            choices: tuningChoices(("Low", "0"), ("Medium", "1"), ("High", "2"))
        ),
        LuaTuningOption(
            id: "shadow-quality",
            title: "Shadows",
            caption: "High has the largest GPU cost in large battles.",
            keyCandidates: ["shadow_quality"],
            choices: tuningChoices(("Off", "0"), ("Low", "1"), ("Medium", "2"), ("High", "3"))
        ),
        LuaTuningOption(
            id: "texture-detail",
            title: "Texture detail",
            caption: "High keeps full-resolution textures.",
            keyCandidates: ["texture_level"],
            choices: tuningChoices(("Low", "2"), ("Medium", "1"), ("High", "0"))
        ),
        LuaTuningOption(
            id: "level-of-detail",
            title: "Level of detail",
            caption: "How long distant units and terrain retain detail.",
            keyCandidates: ["level_of_detail"],
            choices: tuningChoices(("Low", "0"), ("Medium", "1"), ("High", "2"))
        ),
        LuaTuningOption(
            id: "sky-rendering",
            title: "Sky rendering",
            caption: "Off is a troubleshooting fallback for old shader failures.",
            keyCandidates: ["render_skydome", "render_skycube"],
            choices: tuningChoices(("Off", "0"), ("On", "1"))
        ),
        LuaTuningOption(
            id: "bloom",
            title: "Bloom",
            caption: "Soft glow around bright effects; Off is the safer fallback if the scene renders incorrectly.",
            keyCandidates: ["bloom_render"],
            choices: tuningChoices(("Off", "0"), ("On", "1"))
        ),
        LuaTuningOption(
            id: "antialiasing",
            title: "Anti-aliasing",
            caption: "Only Off can be forced safely; supported multisample values vary by graphics adapter.",
            keyCandidates: ["antialiasing"],
            choices: tuningChoices(("Off", "0"))
        ),
        LuaTuningOption(
            id: "vsync",
            title: "Vertical sync",
            caption: "On prevents tearing; Off reduces waiting but can increase heat.",
            keyCandidates: ["vsync"],
            choices: tuningChoices(("Off", "0"), ("On", "1"))
        ),
        volumeTuningOption(
            id: "master-volume",
            title: "Master volume",
            key: "master_volume"
        ),
        volumeTuningOption(
            id: "effects-volume",
            title: "Effects volume",
            key: "fx_volume"
        ),
        volumeTuningOption(
            id: "music-volume",
            title: "Music volume",
            key: "music_volume"
        ),
        volumeTuningOption(
            id: "voice-volume",
            title: "Voice volume",
            key: "vo_volume"
        )
    ]

    private static func volumeTuningOption(
        id: String,
        title: String,
        key: String
    ) -> LuaTuningOption {
        LuaTuningOption(
            id: id,
            title: title,
            caption: "Updates this existing 0–100 game setting; the listed percentages are a compact launcher subset.",
            keyCandidates: [key],
            choices: tuningChoices(
                ("Muted", "0"),
                ("25%", "25"),
                ("50%", "50"),
                ("75%", "75"),
                ("100%", "100")
            )
        )
    }

    private static func tuningChoices(
        _ values: (String, String)...
    ) -> [LuaTuningChoice] {
        [.init(label: QualityOption.gameDefaultLabel, value: "")]
            + values.map { .init(label: $0.0, value: $0.1) }
    }

}
