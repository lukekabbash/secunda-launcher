import Foundation

enum SelfCheck {
    static func run() -> Int32 {
        var failures: [String] = []
        var passes = 0

        let override = SecundaPaths.discoverRepositoryRoot(
            environment: ["SECUNDA_REPOSITORY_ROOT": "/tmp/secunda-source"],
            currentDirectory: URL(fileURLWithPath: "/")
        )
        expect(override?.path == "/tmp/secunda-source", "repository override", passes: &passes, failures: &failures)

        let root = URL(fileURLWithPath: "/tmp/secunda-self-check", isDirectory: true)
        let paths = SecundaPaths(applicationSupport: root, repositoryRoot: nil, environment: [:])
        expect(
            paths.bottleRoot.path.hasPrefix(paths.applicationSupport.path),
            "bottle path containment",
            passes: &passes,
            failures: &failures
        )
        expect(
            paths.logsDirectory.path.hasPrefix(paths.applicationSupport.path),
            "log path containment",
            passes: &passes,
            failures: &failures
        )
        expect(
            paths.backupsDirectory.path.hasPrefix(paths.applicationSupport.path),
            "backup path containment",
            passes: &passes,
            failures: &failures
        )
        expect(
            paths.graphicsCacheDirectory.path.hasPrefix(paths.applicationSupport.path),
            "graphics cache containment",
            passes: &passes,
            failures: &failures
        )
        expect(
            paths.activeWindowsUserDirectory().lastPathComponent == "secunda",
            "managed Windows user fallback",
            passes: &passes,
            failures: &failures
        )
        expect(GameDescriptor.skyrimSE.steamAppID == "489830", "Steam app identifier", passes: &passes, failures: &failures)
        expect(
            GameDescriptor.supported == [
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
            ],
            "supported game registry",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.blackOps2SP.steamAppID == "202970"
                && GameDescriptor.blackOps2MP.steamAppID == "202990"
                && GameDescriptor.blackOps2Zombies.steamAppID == "212910"
                && GameDescriptor.blackOps2SP.gameImageName == "t6sp.exe"
                && GameDescriptor.blackOps2MP.gameImageName == "t6mp.exe"
                && GameDescriptor.blackOps2Zombies.gameImageName == "t6zm.exe",
            "Black Ops II descriptors",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.insurgency.steamAppID == "222880"
                && GameDescriptor.insurgency.executableRelativePath == "insurgency.exe"
                && GameDescriptor.insurgency.gameImageName == "insurgency.exe"
                && GameDescriptor.insurgency.gameProcessImageNames
                    == ["insurgency.exe", "insurgency_x64.exe"]
                && GameDescriptor.insurgency.launcherProcessImageNames.isEmpty
                && GameDescriptor.supremeCommander.steamAppID == "9350"
                && GameDescriptor.supremeCommander.executableRelativePath
                    == "bin/SupremeCommander.exe"
                && GameDescriptor.forgedAlliance.steamAppID == "9420"
                && GameDescriptor.forgedAlliance.executableRelativePath
                    == "bin/SupremeCommander.exe"
                && GameDescriptor.angelsFallFirst.steamAppID == "367270"
                && GameDescriptor.angelsFallFirst.executableRelativePath
                    == "Binaries/Win64/AFFGame.exe"
                && GameDescriptor.battlefront2Classic.steamAppID == "6060"
                && GameDescriptor.battlefront2Classic.executableRelativePath
                    == "GameData/BattlefrontII.exe",
            "classic game descriptors",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.insurgency.baselineDataFile
                == "insurgency/insurgency_materials_000.vpk"
                && GameDescriptor.supremeCommander.baselineDataFile == "gamedata/lua.scd"
                && GameDescriptor.forgedAlliance.baselineDataFile == "gamedata/lua.scd"
                && GameDescriptor.angelsFallFirst.baselineDataFile
                    == "AFFGame/CookedPC/AFFGame.u"
                && GameDescriptor.battlefront2Classic.baselineDataFile
                    == "GameData/data/_lvl_pc/common.lvl"
                && GameDescriptor.supremeCommander.documentsRelativePath.isEmpty
                && GameDescriptor.supremeCommander.luaPrefsRelativePath
                    == "AppData/Local/Gas Powered Games/SupremeCommander/Game.prefs"
                && GameDescriptor.forgedAlliance.documentsRelativePath
                    == "My Games/Gas Powered Games/Supreme Commander Forged Alliance"
                && GameDescriptor.forgedAlliance.luaPrefsRelativePath
                    == "AppData/Local/Gas Powered Games/Supreme Commander Forged Alliance/Game.prefs",
            "classic game install and profile markers",
            passes: &passes,
            failures: &failures
        )
        let classicCatalogFailures = ClassicGameCatalogSelfCheck.failures()
        expect(
            classicCatalogFailures.isEmpty,
            "classic catalog install probes\(classicCatalogFailures.isEmpty ? "" : ": \(classicCatalogFailures.joined(separator: ", "))")",
            passes: &passes,
            failures: &failures
        )
        let classicProfileFailures = ClassicProfileWriterSelfCheck.failures()
        expect(
            classicProfileFailures.isEmpty,
            "classic profile filesystem boundaries\(classicProfileFailures.isEmpty ? "" : ": \(classicProfileFailures.joined(separator: ", "))")",
            passes: &passes,
            failures: &failures
        )
        let queuedInstallRequirement = InstallSpacePolicy.requiredFreeBytes(
            for: .insurgency,
            pending: [.angelsFallFirst, .supremeCommander]
        )
        expect(
            queuedInstallRequirement
                == InstallSpacePolicy.reserveBytes
                    + (GameDescriptor.insurgency.estimatedInstallBytes ?? 0)
                    + (GameDescriptor.angelsFallFirst.estimatedInstallBytes ?? 0)
                    + (GameDescriptor.supremeCommander.estimatedInstallBytes ?? 0),
            "install capacity includes already queued games",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.skyrimSE.usesNativeVoiceAudioFix
                && GameDescriptor.fallout4.usesNativeVoiceAudioFix
                && !GameDescriptor.insurgency.usesNativeVoiceAudioFix
                && !GameDescriptor.supremeCommander.usesNativeVoiceAudioFix
                && !GameDescriptor.forgedAlliance.usesNativeVoiceAudioFix
                && !GameDescriptor.angelsFallFirst.usesNativeVoiceAudioFix
                && !GameDescriptor.battlefront2Classic.usesNativeVoiceAudioFix
                && !GameDescriptor.supcom2.usesNativeVoiceAudioFix
                && !GameDescriptor.blackOps2SP.usesNativeVoiceAudioFix
                && !GameDescriptor.blackOps2MP.usesNativeVoiceAudioFix
                && !GameDescriptor.blackOps2Zombies.usesNativeVoiceAudioFix,
            "native voice fix is title scoped",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.insurgency.prefersNativeSessionDPI
                && !GameDescriptor.insurgency.usesScreenCoveringBorderlessSurface
                && GameDescriptor.insurgency.launchProfile.displayCoordinatePolicy
                    == .backingPixels
                && GameService.sessionRetinaMode(
                    for: .insurgency,
                    displayGeometry: HostDisplayGeometry(
                        fullFramePoints: DisplayExtent(width: 1710, height: 1107),
                        fullscreenContentPoints: DisplayExtent(width: 1710, height: 1074),
                        visibleFramePoints: DisplayExtent(width: 1710, height: 1005),
                        windowedContentPoints: DisplayExtent(width: 1710, height: 973),
                        backingScale: 2,
                        supportsTwoXRetina: true
                    )
                ),
            "backing-pixel display policy stays title scoped",
            passes: &passes,
            failures: &failures
        )
        let inheritedDisplayProfilesRemainExact = GameDescriptor.supported
            .filter { $0.launchProfile.displayCoordinatePolicy == .inherited }
            .allSatisfy { descriptor in
                (try? GameService.backingPixelDisplaySettings(
                    GameSettings(),
                    descriptor: descriptor,
                    displayGeometry: .unknown,
                    retinaMode: false
                )) == GameSettings()
            }
        expect(
            inheritedDisplayProfilesRemainExact,
            "backing-pixel resolver is a no-op for every other title",
            passes: &passes,
            failures: &failures
        )
        // DXVK is reserved for 64-bit Direct3D 9 titles: the 32-bit DXVK
        // path cannot reach Vulkan from WoW64 in this runtime, so every
        // 32-bit game declares the builtin renderer it actually runs on.
        expect(
            GameDescriptor.blackOps2SP.d3d9Backend == .wined3d
                && GameDescriptor.blackOps2MP.d3d9Backend == .wined3d
                && GameDescriptor.blackOps2Zombies.d3d9Backend == .wined3d
                && GameDescriptor.supcom2.d3d9Backend == .wined3d
                && GameDescriptor.insurgency.d3d9Backend == .wined3d
                && GameDescriptor.supremeCommander.d3d9Backend == .wined3d
                && GameDescriptor.forgedAlliance.d3d9Backend == .wined3d
                && GameDescriptor.angelsFallFirst.d3d9Backend == .dxvk
                && GameDescriptor.battlefront2Classic.d3d9Backend == .wined3d
                && GameDescriptor.skyrimSE.d3d9Backend == .wined3d,
            "per-game Direct3D 9 backends",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameGroup.all.count == 8
                && GameGroup.group(for: "black-ops-2")?.componentIDs
                    == ["bo2-campaign", "bo2-multiplayer", "bo2-zombies"]
                && GameGroup.group(for: "supreme-commander")?.componentIDs
                    == ["supreme-commander", "forged-alliance"]
                && GameGroup.group(for: "black-ops-2")?.isMultiComponent == true
                && GameGroup.group(for: "supreme-commander")?.isMultiComponent == true
                && GameGroup.group(for: "skyrim-se")?.isMultiComponent == false,
            "library groups unify multi-component titles",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameGroup.group(containing: "bo2-zombies")?.id == "black-ops-2"
                && GameGroup.all.flatMap(\.componentIDs).sorted()
                    == GameDescriptor.supported.map(\.id).sorted(),
            "every game belongs to exactly one group",
            passes: &passes,
            failures: &failures
        )
        let descriptorIDs = GameDescriptor.supported.map(\.id)
        let groupIDs = GameGroup.all.map(\.id)
        let groupedComponentIDs = GameGroup.all.flatMap(\.componentIDs)
        expect(
            Set(descriptorIDs).count == descriptorIDs.count
                && Set(groupIDs).count == groupIDs.count
                && Set(groupedComponentIDs).count == groupedComponentIDs.count,
            "game and group identifiers are unique",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.blackOps2Zombies.modeTitle == "Zombies"
                && GameDescriptor.blackOps2MP.modeTitle == "Multiplayer"
                && GameDescriptor.supremeCommander.modeTitle == "Original"
                && GameDescriptor.forgedAlliance.modeTitle == "Forged Alliance"
                && GameDescriptor.supcom2.modeTitle == "Supreme Commander 2",
            "component mode titles",
            passes: &passes,
            failures: &failures
        )
        expect(
            DXVKService.isDXVKBinary(Data("...dxvk_config...".utf8))
                && !DXVKService.isDXVKBinary(Data("MZ Wine builtin DLL".utf8)),
            "DXVK binary detection",
            passes: &passes,
            failures: &failures
        )
        expect(
            DXVKService.payload.map(\.destination) == [
                "drive_c/windows/system32/d3d9.dll",
                "drive_c/windows/syswow64/d3d9.dll"
            ],
            "DXVK payload covers both architectures",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.skyrimSE.vsyncKey == "iVSyncPresentInterval"
                && GameDescriptor.fallout4.vsyncKey == "iPresentInterval"
                && GameDescriptor.battlefront2Classic.vsyncKey.isEmpty,
            "per-game vsync keys",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.supcom2.executableRelativePath == "bin/SupremeCommander2.exe"
                && GameDescriptor.supcom2.gameImageName == "SupremeCommander2.exe"
                && !GameDescriptor.supcom2.supportsDisplayProfile
                && GameDescriptor.supcom2.launchProfile.managesResolution
                && !GameDescriptor.supcom2.launchProfile.fitsResolutionToDesktop
                && !GameDescriptor.supcom2.launchProfile.usesTransitionSafeBorderlessSurface
                && GameDescriptor.supcom2.usesScreenCoveringBorderlessSurface
                && !GameDescriptor.insurgency.launchProfile.fitsResolutionToDesktop
                && GameDescriptor.insurgency.launchProfile.managesResolution
                && GameDescriptor.insurgency.launchProfile.exclusiveFullscreenPolicy
                    == .capturedHostMode
                && GameDescriptor.insurgency.launchProfile.displayCoordinatePolicy
                    == .backingPixels
                && GameDescriptor.insurgency.launchProfile.requiresFullDisplayCoverage
                && GameDescriptor.insurgency.supportedDisplayModes == DisplayMode.allCases
                && GameDescriptor.supremeCommander.launchProfile.fitsResolutionToDesktop
                && GameDescriptor.forgedAlliance.launchProfile.fitsResolutionToDesktop,
            "classic display policies remain explicit and isolated",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.supcom2.prefersNativeSessionDPI
                && GameDescriptor.supremeCommander.prefersNativeSessionDPI
                && GameDescriptor.forgedAlliance.prefersNativeSessionDPI
                && GameDescriptor.supcom2.luaPrefsAdapterKeyCandidates.isEmpty
                && GameDescriptor.supremeCommander.luaPrefsAdapterKeyCandidates == ["primary_adapter"]
                && GameDescriptor.forgedAlliance.luaPrefsAdapterKeyCandidates == ["primary_adapter"]
                && GameDescriptor.skyrimSE.luaPrefsAdapterKeyCandidates.isEmpty
                && !GameDescriptor.supcom2.managesLuaDesktopWindow
                && GameDescriptor.supcom2.supportedDisplayModes
                    == [.borderlessFullscreen, .windowed],
            "Supreme Commander 2 keeps its native borderless render-surface contract",
            passes: &passes,
            failures: &failures
        )
        let supcom2Decoration = BottleManager.appMacDriverDecoration(
            application: GameDescriptor.supcom2.gameImageName,
            decorated: false
        )
        let skyrimExclusiveDisplayPolicy = GameService.executableDisplayPolicy(
            descriptor: .skyrimSE,
            displayMode: .exclusiveFullscreen
        )
        let skyrimBorderlessDisplayPolicy = GameService.executableDisplayPolicy(
            descriptor: .skyrimSE,
            displayMode: .borderlessFullscreen
        )
        let skyrimWindowedDisplayPolicy = GameService.executableDisplayPolicy(
            descriptor: .skyrimSE,
            displayMode: .windowed
        )
        let skyrimExclusiveRegistry = skyrimExclusiveDisplayPolicy
            .map(BottleManager.appDisplayPolicyValues) ?? []
        expect(
            supcom2Decoration?.key
                == "HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\SupremeCommander2.exe\\Mac Driver"
                && supcom2Decoration?.name == "Decorated"
                && supcom2Decoration?.type == "REG_SZ"
                && supcom2Decoration?.value == "N"
                && BottleManager.appMacDriverDecoration(application: "bad/path.exe", decorated: false) == nil,
            "native borderless profiles use app-scoped undecorated Mac windows",
            passes: &passes,
            failures: &failures
        )
        expect(
            !GameDescriptor.skyrimSE.launchProfile.requiresVisibleWindow
                && GameDescriptor.skyrimSE.launchProfile.exclusiveFullscreenPolicy
                    == .capturedHostMode
                && skyrimExclusiveDisplayPolicy == ExecutableDisplayPolicy(
                    application: "SkyrimSE.exe",
                    decorated: false,
                    capturesDisplaysForFullscreen: true
                )
                && skyrimBorderlessDisplayPolicy == ExecutableDisplayPolicy(
                    application: "SkyrimSE.exe",
                    decorated: false,
                    capturesDisplaysForFullscreen: false
                )
                && skyrimWindowedDisplayPolicy == ExecutableDisplayPolicy(
                    application: "SkyrimSE.exe",
                    decorated: true,
                    capturesDisplaysForFullscreen: false
                )
                && GameService.executableDisplayPolicy(
                    descriptor: .fallout4,
                    displayMode: .exclusiveFullscreen
                ) == nil,
            "captured fullscreen policy stays scoped to SkyrimSE.exe",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameService.executableDisplayPolicies(
                descriptor: .insurgency,
                displayMode: .borderlessFullscreen
            ).map(\.application) == ["insurgency.exe", "insurgency_x64.exe"]
                && GameService.executableDisplayPolicies(
                    descriptor: .fallout4,
                    displayMode: .borderlessFullscreen
                ).isEmpty,
            "window policy covers every title-scoped final executable only",
            passes: &passes,
            failures: &failures
        )
        expect(
            skyrimExclusiveRegistry.count == 2
                && skyrimExclusiveRegistry[0].key
                    == "HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\SkyrimSE.exe\\X11 Driver"
                && skyrimExclusiveRegistry[0].name == "Decorated"
                && skyrimExclusiveRegistry[0].type == "REG_SZ"
                && skyrimExclusiveRegistry[0].value == "N"
                && skyrimExclusiveRegistry[1].key
                    == "HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\SkyrimSE.exe\\Mac Driver"
                && skyrimExclusiveRegistry[1].name == "CaptureDisplaysForFullscreen"
                && skyrimExclusiveRegistry[1].type == "REG_SZ"
                && skyrimExclusiveRegistry[1].value == "Y"
                && BottleManager.appDisplayPolicyValues(
                    ExecutableDisplayPolicy(
                        application: "bad/path.exe",
                        decorated: false,
                        capturesDisplaysForFullscreen: true
                    )
                ).isEmpty,
            "Skyrim fullscreen writes only executable-scoped Wine window policy",
            passes: &passes,
            failures: &failures
        )
        let windowPlacementSample = "x = 99\nWindows = {\n Main = { y = 37, x = 12 }\n}\n"
        let windowPlacementUpdated = GameProfileWriter.updatingLuaTableNumericValues(
            in: windowPlacementSample,
            tablePath: ["Windows", "Main"],
            values: ["x": "0", "y": "0"]
        )
        expect(
            windowPlacementUpdated.hasPrefix("x = 99")
                && windowPlacementUpdated.contains("Main = { y = 0, x = 0 }")
                && GameProfileWriter.updatingLuaTableNumericValues(
                    in: "x = 99",
                    tablePath: ["Windows", "Main"],
                    values: ["x": "0"]
                ) == "x = 99",
            "Lua window placement rewrite stays inside Windows.Main",
            passes: &passes,
            failures: &failures
        )
        let adapterSample = "options = {\n    primary_adapter = {\n        default = 'overridden',\n    },\n    primary_adapter = '1024,768,60',\n}\n"
        let adapterUpdated = GameProfileWriter.updatingLuaAdapterValue(
            in: adapterSample,
            keyCandidates: ["primary_adapter"],
            width: 1710,
            height: 1107
        )
        expect(
            adapterUpdated.contains("primary_adapter = '1710,1107,60'")
                && adapterUpdated.contains("primary_adapter = {")
                && GameProfileWriter.updatingLuaAdapterValue(
                    in: "primary_adapter = '800,600'",
                    keyCandidates: ["primary_adapter"],
                    width: 1710,
                    height: 1107
                ) == "primary_adapter = '1710,1107'"
                && GameProfileWriter.updatingLuaAdapterValue(
                    in: "unrelated = 3",
                    keyCandidates: ["primary_adapter"],
                    width: 1710,
                    height: 1107
                ) == "unrelated = 3",
            "adapter resolution rewrite preserves refresh rate and table form",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.supcom2.luaPrefsRelativePath
                == "AppData/Local/Gas Powered Games/Supreme Commander 2/Game.prefs"
                && GameDescriptor.supcom2.luaTuningOptions.map(\.id) == ["unit-cap"],
            "Supreme Commander 2 profile writes only the unit cap",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameService.gameArguments(descriptor: .supcom2, settings: GameSettings())
                == ["/windowed", "1920", "1080"]
                && GameService.gameArguments(
                    descriptor: .insurgency,
                    settings: GameSettings()
                ) == [
                    "-novid", "-windowed", "-noborder",
                    "-w", "1920", "-h", "1080"
                ]
                && GameService.gameArguments(
                    descriptor: .supremeCommander,
                    settings: GameSettings()
                ) == ["/windowed", "1920", "1080"]
                && GameService.gameArguments(
                    descriptor: .forgedAlliance,
                    settings: GameSettings()
                ) == ["/windowed", "1920", "1080"]
                && GameService.gameArguments(descriptor: .skyrimSE, settings: GameSettings()).isEmpty,
            "title-scoped resolution arguments",
            passes: &passes,
            failures: &failures
        )
        let supremeCommander2LaunchRecord = GameLaunchRecorder.makeRecord(
            descriptor: .supcom2,
            settings: GameSettings(),
            arguments: ["-applaunch", "40100", "/windowed", "1920", "1080"],
            logPixels: 96,
            retinaMode: false,
            bottleRoot: paths.bottleRoot,
            installRoot: nil,
            now: Date(timeIntervalSince1970: 0)
        )
        expect(
            supremeCommander2LaunchRecord.gameID == "supcom2"
                && supremeCommander2LaunchRecord.recordType == "launch-request"
                && supremeCommander2LaunchRecord.attemptID == "self-check"
                && supremeCommander2LaunchRecord.arguments
                    == ["-applaunch", "40100", "/windowed", "1920", "1080"]
                && supremeCommander2LaunchRecord.logPixels == 96
                && !supremeCommander2LaunchRecord.retinaMode
                && supremeCommander2LaunchRecord.engineLogBeforeLaunch?.relativePath
                    == "drive_c/sc2.log",
            "diagnostic launch record captures the exact Supreme Commander 2 tuple",
            passes: &passes,
            failures: &failures
        )
        var requestedBackingRecordSettings = GameSettings()
        requestedBackingRecordSettings.width = 1920
        requestedBackingRecordSettings.height = 1080
        var effectiveBackingRecordSettings = requestedBackingRecordSettings
        effectiveBackingRecordSettings.width = 3420
        effectiveBackingRecordSettings.height = 2214
        let backingLaunchRecord = GameLaunchRecorder.makeRecord(
            descriptor: .insurgency,
            settings: effectiveBackingRecordSettings,
            arguments: [
                "-applaunch", "222880", "-novid", "-windowed", "-noborder",
                "-w", "3420", "-h", "2214"
            ],
            logPixels: 96,
            retinaMode: true,
            bottleRoot: paths.bottleRoot,
            installRoot: nil,
            requestedSettings: requestedBackingRecordSettings,
            displayGeometry: HostDisplayGeometry(
                fullFramePoints: DisplayExtent(width: 1710, height: 1107),
                fullscreenContentPoints: DisplayExtent(width: 1710, height: 1074),
                visibleFramePoints: DisplayExtent(width: 1710, height: 1005),
                windowedContentPoints: DisplayExtent(width: 1710, height: 973),
                backingScale: 2,
                supportsTwoXRetina: true
            ),
            now: Date(timeIntervalSince1970: 0)
        )
        expect(
            backingLaunchRecord.width == 3420
                && backingLaunchRecord.height == 2214
                && backingLaunchRecord.requestedWidth == 1920
                && backingLaunchRecord.requestedHeight == 1080
                && backingLaunchRecord.screenPointWidth == 1710
                && backingLaunchRecord.screenPixelWidth == 3420
                && backingLaunchRecord.displayCoordinatePolicy == "backingPixels",
            "launch record separates requested, engine, and host geometry",
            passes: &passes,
            failures: &failures
        )
        let insurgencySourceState = GameLaunchRecorder.insurgencyState(from: """
        Driver Name: Example Adapter
        DXLevel: 9.0 Shader Model 3.0
        Vid: 1710 x 1107
        vsync: 1
        cmdline: C:\\private\\path\\insurgency.exe
        """)
        expect(
            insurgencySourceState?.driver == "Example Adapter"
                && insurgencySourceState?.direct3DLevel == "9.0 Shader Model 3.0"
                && insurgencySourceState?.videoMode == "1710 x 1107"
                && insurgencySourceState?.verticalSync == "1"
                && GameLaunchRecorder.recordsFrameOutcome(
                    for: .insurgency,
                    diagnostics: true
                )
                && !GameLaunchRecorder.recordsFrameOutcome(
                    for: .skyrimSE,
                    diagnostics: true
                )
                && !GameLaunchRecorder.recordsFrameOutcome(
                    for: .fallout4,
                    diagnostics: true
                )
                && !GameLaunchRecorder.recordsFrameOutcome(
                    for: .insurgency,
                    diagnostics: false
                ),
            "diagnostic frame outcomes stay allowlisted to verified-surface titles",
            passes: &passes,
            failures: &failures
        )
        expect(
            MacGameFrameProbe.classify(
                firstNonBlackPermille: 0,
                secondNonBlackPermille: 0,
                changedPermille: 0
            ) == .allBlack
                && MacGameFrameProbe.classify(
                    firstNonBlackPermille: 500,
                    secondNonBlackPermille: 500,
                    changedPermille: 0
                ) == .nonBlackStatic
                && MacGameFrameProbe.classify(
                    firstNonBlackPermille: 500,
                    secondNonBlackPermille: 600,
                    changedPermille: 40
                ) == .nonBlackChanging,
            "window frame diagnostics classify black, static, and advancing output",
            passes: &passes,
            failures: &failures
        )
        var insurgencySettings = LauncherSettings().game(.insurgency)
        insurgencySettings.width = 1600
        insurgencySettings.height = 900
        insurgencySettings.verticalSync = false
        insurgencySettings.fieldOfView = 100
        expect(
            GameService.gameArguments(descriptor: .insurgency, settings: insurgencySettings)
                == ["-novid", "-windowed", "-noborder", "-w", "1600", "-h", "900"],
            "borderless arguments retain borderless engine semantics",
            passes: &passes,
            failures: &failures
        )
        insurgencySettings.displayMode = .exclusiveFullscreen
        expect(
            GameService.gameArguments(descriptor: .insurgency, settings: insurgencySettings)
                == ["-novid", "-fullscreen", "-w", "1600", "-h", "900"],
            "exclusive arguments retain exclusive engine semantics",
            passes: &passes,
            failures: &failures
        )
        insurgencySettings.displayMode = .windowed
        expect(
            GameService.gameArguments(descriptor: .insurgency, settings: insurgencySettings)
                == ["-novid", "-windowed", "-w", "1600", "-h", "900"],
            "windowed arguments preserve the selected client size",
            passes: &passes,
            failures: &failures
        )
        var battlefrontSettings = LauncherSettings().game(.battlefront2Classic)
        expect(
            battlefrontSettings.displayMode == .windowed
                && GameService.gameArguments(
                    descriptor: .battlefront2Classic,
                    settings: battlefrontSettings
                ) == ["/win", "/resolution", "1920", "1080"],
            "Battlefront II default windowed resolution arguments",
            passes: &passes,
            failures: &failures
        )
        battlefrontSettings.displayMode = .exclusiveFullscreen
        battlefrontSettings.tuning["audio-buffer"] = "Compatibility (200 ms)"
        expect(
            GameService.gameArguments(
                descriptor: .battlefront2Classic,
                settings: battlefrontSettings
            ) == [
                "/resolution", "1920", "1080", "/audiomixbuffer", "200"
            ],
            "Battlefront II fullscreen and audio compatibility arguments",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.angelsFallFirst.launcherImageName == "AFFLift.exe"
                && GameDescriptor.angelsFallFirst.processImageNames.contains("AFFGame.exe")
                && GameDescriptor.angelsFallFirst.launcherProcessImageNames == ["AFFLift.exe"]
                && GameService.gameArguments(
                    descriptor: .angelsFallFirst,
                    settings: LauncherSettings().game(.angelsFallFirst)
                ) == ["-windowed"]
                && GameService.directGameArguments(
                    descriptor: .angelsFallFirst,
                    settings: GameSettings()
                ) == ["-SEEKFREELOADING", "-DX9", "-windowed"]
                && GameDescriptor.angelsFallFirst.launchProfile.requiresVisibleWindow
                && GameDescriptor.insurgency.launchProfile.requiresVisibleWindow,
            "Steam-running native game launch arguments",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.insurgency.managedDisplayCapabilities
                == ManagedDisplayCapabilities(
                    modes: DisplayMode.allCases,
                    resolution: true,
                    verticalSync: true,
                    fieldOfView: false
                ),
            "Insurgency display settings are written through live video.txt",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.supremeCommander.managedDisplayCapabilities
                == ManagedDisplayCapabilities(
                    modes: [.borderlessFullscreen, .windowed],
                    resolution: true,
                    verticalSync: false,
                    fieldOfView: false
                ),
            "Supreme Commander display capabilities",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.angelsFallFirst.managedDisplayCapabilities
                == ManagedDisplayCapabilities(
                    modes: [],
                    resolution: false,
                    verticalSync: false,
                    fieldOfView: false
                )
                && GameDescriptor.angelsFallFirst.managedINIProfiles.isEmpty
                && GameDescriptor.angelsFallFirst.qualityOptions.isEmpty,
            "Angels Fall First keeps its proven launch tuple but no unaccepted settings",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.battlefront2Classic.supportedDisplayModes
                == [.exclusiveFullscreen, .windowed],
            "Battlefront II display capabilities",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.supremeCommander.luaTuningOptions.map(\.id) == [
                "fidelity", "shadow-quality", "texture-detail", "level-of-detail",
                "sky-rendering", "bloom", "antialiasing", "vsync",
                "master-volume", "effects-volume", "music-volume", "voice-volume"
            ] && GameDescriptor.forgedAlliance.luaTuningOptions
                == GameDescriptor.supremeCommander.luaTuningOptions,
            "Supreme Commander existing-key tuning map",
            passes: &passes,
            failures: &failures
        )
        let masterVolume = GameDescriptor.supremeCommander.luaTuningOptions
            .first { $0.id == "master-volume" }
        expect(
            masterVolume?.keyCandidates == ["master_volume"]
                && masterVolume?.choices.map(\.value) == ["", "0", "25", "50", "75", "100"],
            "Supreme Commander schema-safe volume choices",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.supcom2.luaTuningOptions.map(\.id) == ["unit-cap"],
            "Supreme Commander 2 exposes only unit-cap tuning",
            passes: &passes,
            failures: &failures
        )
        expect(GameDescriptor.skyrimSE.gameImageName == "SkyrimSE.exe", "descriptor game image", passes: &passes, failures: &failures)
        expect(GameDescriptor.fallout4.steamAppID == "377160", "Fallout 4 app identifier", passes: &passes, failures: &failures)
        expect(GameDescriptor.fallout4.gameImageName == "Fallout4.exe", "Fallout 4 game image", passes: &passes, failures: &failures)
        expect(
            GameDescriptor.skyrimSE.baselineDataFile == "Data/Skyrim.esm"
                && GameDescriptor.fallout4.baselineDataFile == "Data/Fallout4.esm",
            "per-game baseline data files",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.descriptor(for: "fallout-4") == .fallout4
                && GameDescriptor.descriptor(for: "missing") == nil,
            "descriptor lookup",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameSnapshot().state == .working("Checking"),
            "unprobed game state is checking, not missing",
            passes: &passes,
            failures: &failures
        )
        expect(
            BottleProcessInspector.matchesImages(
                "C:\\Games\\bin\\SupremeCommander2.exe /windowed 1920 1080",
                images: [GameDescriptor.supcom2.gameImageName, GameDescriptor.supcom2.launcherImageName]
            ),
            "running-game detection matches windowed command lines",
            passes: &passes,
            failures: &failures
        )
        let classicProcess = BottleProcess(
            pid: 999,
            ppid: 1,
            command: "C:\\games\\insurgency.exe -console"
        )
        expect(
            GameService.activeGame(in: [classicProcess]) == .insurgency
                && GameService.activeGame(in: [BottleProcess(
                    pid: 1_000,
                    ppid: 10,
                    command: "C:\\games\\insurgency_x64.exe -console"
                )]) == .insurgency
                && BottleProcessInspector.matchesImages(
                    "C:\\games\\insurgency_x64.exe -console",
                    images: GameDescriptor.insurgency.gameProcessImageNames
                )
                && GameService.sharesProcessIdentity(.supremeCommander, .forgedAlliance)
                && !GameService.sharesProcessIdentity(.insurgency, .angelsFallFirst),
            "shared game-space launch guard identifies active titles",
            passes: &passes,
            failures: &failures
        )

        let psFixture = """
          123     1 /Users/t/Bottles/SkyrimSE/drive_c/Games/Fallout4.exe -arg one
          456   123 C:\\windows\\system32\\winedevice.exe
        garbage line
          789    10 /usr/bin/unrelated
        """
        let parsedProcesses = BottleProcessInspector.parse(psOutput: psFixture)
        expect(
            parsedProcesses.count == 3
                && parsedProcesses[0].pid == 123
                && parsedProcesses[0].isOrphaned
                && parsedProcesses[0].command == "/Users/t/Bottles/SkyrimSE/drive_c/Games/Fallout4.exe -arg one"
                && parsedProcesses[1].pid == 456
                && !parsedProcesses[1].isOrphaned,
            "ps output parsing and orphan detection",
            passes: &passes,
            failures: &failures
        )
        expect(
            parsedProcesses[0].displayName == "Fallout4.exe"
                && parsedProcesses[1].displayName == "winedevice.exe",
            "process display names from unix and windows paths",
            passes: &passes,
            failures: &failures
        )
        expect(
            BottleProcessInspector.matches(
                parsedProcesses[0],
                bottlesDirectory: "/Users/t/Bottles",
                executablePath: nil,
                runtimeRoot: "/opt/runtime"
            )
                && BottleProcessInspector.matches(
                    parsedProcesses[1],
                    bottlesDirectory: "/Users/t/Bottles",
                    executablePath: "/opt/runtime/bin/wine64-preloader",
                    runtimeRoot: "/opt/runtime"
                )
                && !BottleProcessInspector.matches(
                    parsedProcesses[2],
                    bottlesDirectory: "/Users/t/Bottles",
                    executablePath: "/usr/bin/unrelated",
                    runtimeRoot: "/opt/runtime"
                ),
            "game-space process matching by bottle path and runtime executable",
            passes: &passes,
            failures: &failures
        )
        expect(
            BottleProcessInspector.matches(
                BottleProcess(
                    pid: 4_242,
                    ppid: 1,
                    command: "/Users/t/Bottles/SkyrimSE-BO2Lab/drive_c/Games/t6mp.exe"
                ),
                bottlesDirectory: "/Users/t/Bottles",
                executablePath: nil,
                runtimeRoot: "/opt/runtime"
            )
                && BottleProcessInspector.matches(
                    parsedProcesses[2],
                    bottlesDirectory: "/Users/t/Bottles",
                    executablePath: "/opt/other-runtime/bin/wineserver",
                    runtimeRoot: "/opt/runtime",
                    executableInProvenancedRuntime: true
                )
                && !BottleProcessInspector.matches(
                    parsedProcesses[2],
                    bottlesDirectory: "/Users/t/Bottles",
                    executablePath: "/opt/other-runtime/bin/wineserver",
                    runtimeRoot: "/opt/runtime",
                    executableInProvenancedRuntime: false
                ),
            "sibling bottles and provenanced foreign runtimes stay visible for cleanup",
            passes: &passes,
            failures: &failures
        )
        let provenancedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("secunda-provenance-\(UUID().uuidString)", isDirectory: true)
        let provenancedLoader = provenancedRoot
            .appendingPathComponent("lib/wine/x86_64-unix/wine")
        do {
            let manifest = provenancedRoot
                .appendingPathComponent(SourceRuntimePolicy.provenanceRelativePath)
            try FileManager.default.createDirectory(
                at: manifest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("{}".utf8).write(to: manifest)
            try FileManager.default.createDirectory(
                at: provenancedLoader.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: provenancedLoader)
        } catch {}
        expect(
            BottleProcessInspector.isInsideProvenancedRuntime(provenancedLoader.path)
                && BottleProcessInspector.isInsideProvenancedRuntime(
                    provenancedRoot.appendingPathComponent("bin/wineserver").path
                )
                && !BottleProcessInspector.isInsideProvenancedRuntime("/usr/bin/true"),
            "provenance walk finds runtime roots from unix loader and server paths",
            passes: &passes,
            failures: &failures
        )
        try? FileManager.default.removeItem(at: provenancedRoot)
        expect(
            BottleProcessInspector.matchesImages(
                "z:\\games\\FALLOUT4.EXE -windowed",
                images: ["Fallout4.exe", "Fallout4Launcher.exe"]
            )
                && !BottleProcessInspector.matchesImages(
                    "/bottle/SkyrimSE.exe",
                    images: ["Fallout4.exe", "Fallout4Launcher.exe"]
                ),
            "per-game image filter is case-insensitive",
            passes: &passes,
            failures: &failures
        )
        expect(
            PrimaryAction.locateRuntime.title(for: .skyrimSE) == "Open Setup Help",
            "truthful source runtime recovery action",
            passes: &passes,
            failures: &failures
        )
        expect(
            PrimaryAction.play.title(for: .fallout4) == "Play Fallout 4"
                && PrimaryAction.installGame.title(for: .skyrimSE) == "Install Skyrim",
            "per-game action titles",
            passes: &passes,
            failures: &failures
        )
        expect(
            SteamService.compatibilityArguments.contains("-system-composer")
                && SteamService.compatibilityArguments.contains("-cef-allow-browser-underlays")
                && SteamService.compatibilityArguments.contains("-no-cef-sandbox"),
            "Steam UI compatibility arguments",
            passes: &passes,
            failures: &failures
        )
        let sourceRuntime = RuntimeDescriptor(
            wineExecutable: URL(fileURLWithPath: "/tmp/secunda/wine"),
            version: "11.0",
            origin: .sourceBuild,
            bottleRoot: paths.bottleRoot
        )
        expect(
            sourceRuntime.wineArguments(for: ["reg", "query"]) == ["reg", "query"],
            "source runtime command arguments",
            passes: &passes,
            failures: &failures
        )
        let runtimeEnvironment = RuntimeManager(
            paths: paths,
            processRunner: ProcessRunner()
        ).environment(for: sourceRuntime, diagnostics: false)
        expect(
            runtimeEnvironment["SECUNDA_CEF_IN_PROCESS_GPU"] == "1",
            "embedded browser compositor mode",
            passes: &passes,
            failures: &failures
        )
        let diagnosticEnvironment = RuntimeManager(
            paths: paths,
            processRunner: ProcessRunner()
        ).environment(for: sourceRuntime, diagnostics: true)
        expect(
            runtimeEnvironment["WINEDEBUG"] == "-all"
                && diagnosticEnvironment["WINEDEBUG"] == "-all,err+all",
            "bounded Wine diagnostic channels",
            passes: &passes,
            failures: &failures
        )
        expect(
            runtimeEnvironment["WINEMSYNC"] == "1" && runtimeEnvironment["WINEESYNC"] == nil,
            "Apple synchronization mode",
            passes: &passes,
            failures: &failures
        )
        let bundledRuntime = RuntimeDescriptor(
            wineExecutable: URL(fileURLWithPath: "/tmp/secunda-bundled/bin/wine"),
            version: "11.0",
            origin: .bundled,
            bottleRoot: paths.bottleRoot
        )
        let bundledEnvironment = RuntimeManager(
            paths: paths,
            processRunner: ProcessRunner()
        ).environment(for: bundledRuntime, diagnostics: false)
        expect(
            runtimeEnvironment["DYLD_LIBRARY_PATH"] != nil
                && bundledEnvironment["DYLD_LIBRARY_PATH"] == "/tmp/secunda-bundled/lib",
            "every runtime origin exposes its library path for soname dlopens",
            passes: &passes,
            failures: &failures
        )
        expect(
            SourceRuntimePolicy.containsForbiddenReference(
                "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"
            ),
            "forbidden application path",
            passes: &passes,
            failures: &failures
        )
        expect(
            SourceRuntimePolicy.containsForbiddenReference("/runtime/lib64/apple_gptk/d3d11.dll"),
            "forbidden graphics payload path",
            passes: &passes,
            failures: &failures
        )
        expect(
            SourceRuntimePolicy.containsForbiddenReference("/runtime/lib/libd3dshared.dylib"),
            "forbidden shared graphics library",
            passes: &passes,
            failures: &failures
        )

        let runtimeFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("secunda-policy-\(UUID().uuidString)", isDirectory: true)
        let fixtureExecutable = runtimeFixture.appendingPathComponent("bin/wine")
        let fixtureManifest = runtimeFixture.appendingPathComponent(
            SourceRuntimePolicy.provenanceRelativePath
        )
        try? FileManager.default.createDirectory(
            at: fixtureManifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let validManifest = """
        {
          "formatVersion": 1,
          "runtimeKind": "secunda-source-runtime",
          "architecture": "x86_64",
          "components": [
            {"name": "Wine", "version": "11.0"},
            {"name": "DXMT", "version": "0.80"}
          ]
        }
        """
        try? Data(validManifest.utf8).write(to: fixtureManifest, options: .atomic)
        expect(
            SourceRuntimePolicy.allows(
                executable: fixtureExecutable,
                trustedRuntimeRoot: runtimeFixture
            ),
            "valid source runtime provenance",
            passes: &passes,
            failures: &failures
        )
        expect(
            !SourceRuntimePolicy.allows(
                executable: fixtureExecutable,
                trustedRuntimeRoot: runtimeFixture.deletingLastPathComponent()
                    .appendingPathComponent("different-runtime")
            ),
            "runtime root containment",
            passes: &passes,
            failures: &failures
        )
        try? Data("{}".utf8).write(to: fixtureManifest, options: .atomic)
        expect(
            !SourceRuntimePolicy.allows(
                executable: fixtureExecutable,
                trustedRuntimeRoot: runtimeFixture
            ),
            "malformed source runtime provenance",
            passes: &passes,
            failures: &failures
        )
        try? FileManager.default.removeItem(at: runtimeFixture)

        let sanitized = SourceRuntimePolicy.sanitizedEnvironment(
            base: [
                "AUTH_TOKEN": "must-not-reach-wine",
                "CX_BOTTLE_PATH": "/tmp/external",
                "DYLD_LIBRARY_PATH": "/Applications/CrossOver.app/Contents/Libraries",
                "HOME": "/Users/tester",
                "LANG": "en_US.UTF-8",
                "PATH": "/usr/bin:/bin",
                "SSH_AUTH_SOCK": "/tmp/agent.sock",
                "STEAM_PASSWORD": "must-not-reach-wine",
                "SteamLogin": "must-not-reach-wine",
                "TMPDIR": "/tmp/secunda"
            ],
            overrides: [
                "WINEPREFIX": paths.bottleRoot.path,
                "PATH": "/tmp/secunda/bin:/usr/bin:/bin",
                "SteamAppId": GameDescriptor.skyrimSE.steamAppID,
                "SteamGameId": GameDescriptor.skyrimSE.steamAppID,
                "CX_ROOT": "/tmp/external",
                "WINEDLLPATH": "/Applications/CrossOver.app/Contents/Libraries"
            ]
        )
        expect(sanitized["CX_BOTTLE_PATH"] == nil, "foreign bottle environment removal", passes: &passes, failures: &failures)
        expect(sanitized["DYLD_LIBRARY_PATH"] == nil, "inherited library path removal", passes: &passes, failures: &failures)
        expect(sanitized["WINEDLLPATH"] == nil, "forbidden override rejection", passes: &passes, failures: &failures)
        expect(sanitized["CX_ROOT"] == nil, "foreign runtime override removal", passes: &passes, failures: &failures)
        expect(sanitized["AUTH_TOKEN"] == nil, "parent secret removal", passes: &passes, failures: &failures)
        expect(sanitized["SSH_AUTH_SOCK"] == nil, "parent credential socket removal", passes: &passes, failures: &failures)
        expect(
            sanitized["STEAM_PASSWORD"] == nil && sanitized["SteamLogin"] == nil,
            "Steam credential environment removal",
            passes: &passes,
            failures: &failures
        )
        expect(
            sanitized["SteamAppId"] == GameDescriptor.skyrimSE.steamAppID
                && sanitized["SteamGameId"] == GameDescriptor.skyrimSE.steamAppID,
            "public Steam game identifiers",
            passes: &passes,
            failures: &failures
        )
        expect(
            sanitized["HOME"] == "/Users/tester"
                && sanitized["LANG"] == "en_US.UTF-8"
                && sanitized["TMPDIR"] == "/tmp/secunda",
            "required host environment preservation",
            passes: &passes,
            failures: &failures
        )
        expect(sanitized["WINEPREFIX"] == paths.bottleRoot.path, "managed prefix override", passes: &passes, failures: &failures)
        expect(
            sanitized["PATH"] == "/tmp/secunda/bin:/usr/bin:/bin",
            "managed executable path",
            passes: &passes,
            failures: &failures
        )

        let launcherSettings = LauncherSettings()
        let settings = launcherSettings.game(.skyrimSE)
        expect(settings.displayMode == .borderlessFullscreen, "display defaults", passes: &passes, failures: &failures)
        expect(settings.verticalSync, "vsync defaults", passes: &passes, failures: &failures)
        expect(settings.fieldOfView == 80, "descriptor field of view default", passes: &passes, failures: &failures)
        expect(settings.nativeVoiceAudio, "voice audio default", passes: &passes, failures: &failures)
        expect(!launcherSettings.enableDiagnostics, "diagnostic defaults", passes: &passes, failures: &failures)
        expect(
            launcherSettings.useFastSync && launcherSettings.activeFastSync,
            "fast synchronization requested and active defaults",
            passes: &passes,
            failures: &failures
        )
        expect(settings.width == 1920 && settings.height == 1080, "resolution defaults", passes: &passes, failures: &failures)
        let aspectMatchedWindows = DisplayResolutionCatalog.options(
            screenWidth: 1710,
            screenHeight: 1107,
            currentWidth: 1920,
            currentHeight: 1080
        )
        expect(
            aspectMatchedWindows.prefix(4).map(\.id)
                == ["1710x1107", "1436x930", "1282x830", "1026x664"]
                && aspectMatchedWindows.contains { $0.id == "1920x1080" }
                && aspectMatchedWindows.contains { $0.id == "1440x900" }
                && aspectMatchedWindows.contains { $0.id == "3840x2160" },
            "resolution choices lead with the display aspect and retain the current selection",
            passes: &passes,
            failures: &failures
        )
        let retinaDisplayOptions = DisplayResolutionCatalog.options(
            screenWidth: 1920,
            screenHeight: 1080,
            currentWidth: 1920,
            currentHeight: 1080,
            screenPixelWidth: 3840,
            screenPixelHeight: 2160
        )
        expect(
            retinaDisplayOptions.prefix(2).map(\.id) == ["1920x1080", "3840x2160"]
                && retinaDisplayOptions[1].note == "Native Pixels",
            "Retina displays expose their native pixel resolution",
            passes: &passes,
            failures: &failures
        )
        let capturedExclusiveOptions = DisplayResolutionCatalog.capturedExclusiveOptions(
            modes: [
                DisplayExtent(width: 1280, height: 800),
                DisplayExtent(width: 1710, height: 1107),
                DisplayExtent(width: 1024, height: 768),
                DisplayExtent(width: 1280, height: 800)
            ],
            active: DisplayExtent(width: 1710, height: 1107)
        )
        expect(
            capturedExclusiveOptions.map(\.id)
                == ["1710x1107", "1280x800", "1024x768"]
                && capturedExclusiveOptions.first?.note == "Current Display Mode"
                && capturedExclusiveOptions[1].note == "Switchable Display Mode"
                && DisplayResolutionCatalog.capturedExclusiveOptions(
                    modes: [DisplayExtent(width: 0, height: 1107)],
                    active: nil
                ).isEmpty,
            "captured exclusive mode exposes every unique switchable host mode",
            passes: &passes,
            failures: &failures
        )
        let hostRetinaModes = HostDisplayModes(
            active: DisplayExtent(width: 1710, height: 1107),
            activePixels: DisplayExtent(width: 3420, height: 2214),
            switchable: [
                DisplayExtent(width: 1710, height: 1107),
                DisplayExtent(width: 1280, height: 800)
            ]
        )
        let wineRetinaModes = hostRetinaModes.wineCoordinates(retinaMode: true)
        expect(
            hostRetinaModes.supportsTwoXRetina
                && wineRetinaModes.active == DisplayExtent(width: 3420, height: 2214)
                && wineRetinaModes.switchable == [
                    DisplayExtent(width: 3420, height: 2214),
                    DisplayExtent(width: 1280, height: 800)
                ]
                && hostRetinaModes.wineCoordinates(retinaMode: false) == hostRetinaModes,
            "Wine display catalog doubles only the active Retina mode",
            passes: &passes,
            failures: &failures
        )
        var fittingSettings = settings
        fittingSettings.width = 1440
        fittingSettings.height = 900
        expect(
            GameProfileWriter.sessionLogPixels(settings: fittingSettings, screenPixelWidth: 3420) == 216,
            "standard DPI preserved for the accepted 1440x900 profile",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.sessionLogPixels(settings: settings, screenPixelWidth: 3420) == 96,
            "1920-wide session maps 1:1 on a 3420-pixel panel",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.sessionLogPixels(
                settings: settings,
                screenPixelWidth: 3420,
                prefersNative: GameDescriptor.insurgency.prefersNativeSessionDPI,
                managesResolution: GameDescriptor.insurgency.managedDisplayCapabilities.resolution
            ) == 96,
            "native input DPI remains independent from backing-pixel output",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.sessionLogPixels(
                settings: settings,
                screenPixelWidth: 3420,
                prefersNative: GameDescriptor.supcom2.prefersNativeSessionDPI,
                managesResolution: GameDescriptor.supcom2.managedDisplayCapabilities.resolution
            ) == 96,
            "Supreme Commander 2 uses native point-space display scaling",
            passes: &passes,
            failures: &failures
        )
        var nativeSettings = settings
        nativeSettings.width = 3420
        nativeSettings.height = 2214
        expect(
            GameProfileWriter.sessionLogPixels(settings: nativeSettings, screenPixelWidth: 3420) == 96,
            "native-resolution session drops to 96 DPI",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.sessionLogPixels(settings: nativeSettings, screenPixelWidth: 0) == 216,
            "unknown screen keeps standard DPI",
            passes: &passes,
            failures: &failures
        )
        expect(
            VoiceAudioService.nativeDLLBaseNames == ["x3daudio1_7", "xactengine3_7", "xaudio2_7"],
            "voice audio override names",
            passes: &passes,
            failures: &failures
        )
        expect(
            VoiceAudioService.isWinePlaceholder(Data("MZ Wine placeholder DLL rest".utf8))
                && !VoiceAudioService.isWinePlaceholder(Data("MZ genuine microsoft bytes".utf8)),
            "voice audio placeholder detection",
            passes: &passes,
            failures: &failures
        )

        let setupProgress = SetupProgress(
            step: 2,
            totalSteps: 4,
            title: "Installing",
            detail: "Test"
        )
        expect(setupProgress.fraction == 0.25, "truthful in-progress fraction", passes: &passes, failures: &failures)
        expect(setupProgress.stepLabel == "Step 2 of 4", "setup progress label", passes: &passes, failures: &failures)

        let handoffChecks = LauncherHandoffSelfCheck.run(root: root, paths: paths)
        passes += handoffChecks.passes
        failures.append(contentsOf: handoffChecks.failures)

        expect(
            ProcessRunnerSelfCheck.captureCompletesWhenChildInheritsOutput(),
            "bounded process capture ignores inherited output handles",
            passes: &passes,
            failures: &failures
        )
        expect(
            ProcessRunnerSelfCheck.capturePreservesMultipleChunksInOrder(),
            "bounded process capture preserves multi-chunk output order",
            passes: &passes,
            failures: &failures
        )

        let profile = GameProfileWriter.updatingDisplaySection(
            in: "[Display]\r\nbFull Screen=1\r\n[Audio]\r\nfMusicDuckingSeconds=6.0\r\n",
            settings: settings
        )
        expect(profile.contains("bFull Screen=0"), "borderless profile disables exclusive fullscreen", passes: &passes, failures: &failures)
        expect(profile.contains("bBorderless=1"), "borderless profile", passes: &passes, failures: &failures)
        expect(profile.contains("iVSyncPresentInterval=1"), "vsync profile", passes: &passes, failures: &failures)
        expect(profile.contains("iSize W=1920"), "profile width", passes: &passes, failures: &failures)
        expect(profile.contains("[Audio]"), "profile preservation", passes: &passes, failures: &failures)

        let crlfINI = "[Display]\r\n; keep this comment\r\nbSAOEnable=1\r\n[Audio]\r\nfMusic=1\r\n"
        let crlfMerged = GameProfileWriter.mergingSectionValues(
            ["bSAOEnable": "0", "fShadowDistance": "4000"],
            into: crlfINI,
            section: "Display"
        )
        var repeatedlyMerged = crlfMerged
        for _ in 0..<9 {
            repeatedlyMerged = GameProfileWriter.mergingSectionValues(
                ["bSAOEnable": "0", "fShadowDistance": "4000"],
                into: repeatedlyMerged,
                section: "Display"
            )
        }
        expect(
            crlfMerged
                == "[Display]\r\n; keep this comment\r\nbSAOEnable=0\r\nfShadowDistance=4000\r\n[Audio]\r\nfMusic=1\r\n"
                && GameProfileWriter.mergingSectionValues(
                    ["bSAOEnable": "0", "fShadowDistance": "4000"],
                    into: crlfMerged,
                    section: "Display"
                ) == crlfMerged
                && repeatedlyMerged == crlfMerged,
            "CRLF profile merge is byte-stable",
            passes: &passes,
            failures: &failures
        )
        let lfMerged = GameProfileWriter.mergingSectionValues(
            ["bSAOEnable": "0"],
            into: "[Display]\nbSAOEnable=1",
            section: "Display"
        )
        expect(
            lfMerged == "[Display]\nbSAOEnable=0"
                && GameProfileWriter.mergingSectionValues(
                    ["bSAOEnable": "0"],
                    into: lfMerged,
                    section: "Display"
                ) == lfMerged,
            "LF profile merge preserves its separator and stabilizes",
            passes: &passes,
            failures: &failures
        )
        let crMerged = GameProfileWriter.mergingSectionValues(
            ["bSAOEnable": "0"],
            into: "[Display]\rbSAOEnable=1\r",
            section: "Display"
        )
        expect(
            crMerged == "[Display]\rbSAOEnable=0\r"
                && GameProfileWriter.mergingSectionValues(
                    ["bSAOEnable": "0"],
                    into: crMerged,
                    section: "Display"
                ) == crMerged,
            "legacy-CR profile merge preserves its separator and stabilizes",
            passes: &passes,
            failures: &failures
        )
        let trailingBlankINI = "[Display]\r\nbSAOEnable=1\r\n\r\n"
        let trailingBlankMerged = GameProfileWriter.mergingSectionValues(
            ["bSAOEnable": "0"],
            into: trailingBlankINI,
            section: "Display"
        )
        expect(
            trailingBlankMerged == "[Display]\r\nbSAOEnable=0\r\n\r\n"
                && GameProfileWriter.mergingSectionValues(
                    ["bSAOEnable": "0"],
                    into: trailingBlankMerged,
                    section: "Display"
                ) == trailingBlankMerged,
            "profile merge preserves trailing blank lines",
            passes: &passes,
            failures: &failures
        )
        let missingSectionMerged = GameProfileWriter.mergingSectionValues(
            ["bSAOEnable": "0"],
            into: "[General]\nsLanguage=ENGLISH\n; final",
            section: "Display"
        )
        expect(
            missingSectionMerged
                == "[General]\nsLanguage=ENGLISH\n; final\n\n[Display]\nbSAOEnable=0"
                && GameProfileWriter.mergingSectionValues(
                    ["bSAOEnable": "0"],
                    into: missingSectionMerged,
                    section: "Display"
                ) == missingSectionMerged,
            "missing section insertion preserves order and terminal-newline state",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.mergingSectionValues(
                ["bSAOEnable": "0"],
                into: "",
                section: "Display"
            ) == "[Display]\r\nbSAOEnable=0\r\n"
                && GameProfileWriter.mergingSectionValues(
                    [:],
                    into: crlfINI,
                    section: "Display"
                ) == crlfINI,
            "empty profile creation and empty merge are deterministic",
            passes: &passes,
            failures: &failures
        )

        var exclusiveSettings = GameSettings()
        exclusiveSettings.displayMode = .exclusiveFullscreen
        let exclusiveProfile = GameProfileWriter.updatingDisplaySection(
            in: "[Display]\r\n",
            settings: exclusiveSettings
        )
        expect(exclusiveProfile.contains("bFull Screen=1"), "exclusive fullscreen profile", passes: &passes, failures: &failures)
        expect(exclusiveProfile.contains("bBorderless=0"), "exclusive borderless off", passes: &passes, failures: &failures)

        let customProfile = GameProfileWriter.updatingCustomDisplaySection(
            in: "[General]\r\nsLanguage=ENGLISH\r\n",
            settings: settings
        )
        expect(customProfile.contains("fDefaultWorldFOV=80"), "world FOV profile", passes: &passes, failures: &failures)
        expect(customProfile.contains("fDefault1stPersonFOV=80"), "first-person FOV profile", passes: &passes, failures: &failures)
        expect(customProfile.contains("sLanguage=ENGLISH"), "custom ini preservation", passes: &passes, failures: &failures)
        expect(
            GameDescriptor.skyrimSE.customIniValues.isEmpty,
            "Skyrim profile carries no failed custom INI experiments",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.mergingExistingSectionValues(
                ["ResX": "1920"],
                into: "[Other]\nResX=800\n",
                section: "SystemSettings"
            ) == "[Other]\nResX=800\n",
            "generated INI merge never creates a missing section",
            passes: &passes,
            failures: &failures
        )
        let sourceVideoProfile = """
        "config"
        {
            "setting.fullscreen"    "1"
            "setting.nowindowborder"    "0"
            "setting.defaultres"    "1520"
            "setting.defaultresheight"    "984"
            "setting.mat_vsync"    "1"
            "preserve"    "yes"
        }
        """
        let sourceVideoUpdated = GameProfileWriter.mergingExistingQuotedKeyValues(
            [
                "setting.fullscreen": "0",
                "setting.nowindowborder": "1",
                "setting.defaultres": "1710",
                "setting.defaultresheight": "1107",
                "setting.mat_vsync": "0"
            ],
            into: sourceVideoProfile
        )
        expect(
            sourceVideoUpdated.contains("\"setting.fullscreen\"    \"0\"")
                && sourceVideoUpdated.contains("\"setting.nowindowborder\"    \"1\"")
                && sourceVideoUpdated.contains("\"setting.defaultres\"    \"1710\"")
                && sourceVideoUpdated.contains("\"setting.defaultresheight\"    \"1107\"")
                && sourceVideoUpdated.contains("\"setting.mat_vsync\"    \"0\"")
                && sourceVideoUpdated.contains("\"preserve\"    \"yes\"")
                && GameProfileWriter.containsManagedFields(
                    GameDescriptor.insurgency.managedINIProfiles[0],
                    in: sourceVideoProfile
                ),
            "quoted Source video profile rewrites only existing keys",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.angelsFallFirst.managedINIProfiles.isEmpty
                && GameDescriptor.angelsFallFirst.qualityOptions.isEmpty,
            "Angels Fall First has no generated configuration contract",
            passes: &passes,
            failures: &failures
        )
        expect(
            SaveService(paths: paths, descriptor: .battlefront2Classic)
                .saveDirectory(in: paths.bottleRoot) == nil
                && GameDescriptor.battlefront2Classic.documentsRelativePath.isEmpty
                && GameDescriptor.battlefront2Classic.saveFileExtensions.isEmpty
                && GameDescriptor.battlefront2Classic.prefsFileName == nil
                && GameDescriptor.battlefront2Classic.customIniFileName == nil
                && GameDescriptor.battlefront2Classic.luaPrefsRelativePath == nil
                && GameDescriptor.battlefront2Classic.qualityOptions.isEmpty,
            "Battlefront II opaque profile and save boundary",
            passes: &passes,
            failures: &failures
        )
        let affExecutableFixture = URL(
            fileURLWithPath: "/tmp/steamapps/common/Angels Fall First/Binaries/Win64/AFFGame.exe"
        )
        expect(
            GameDescriptor.angelsFallFirst.installationRoot(containing: affExecutableFixture)?.path
                == "/tmp/steamapps/common/Angels Fall First",
            "nested executable resolves verified Steam install root",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.fallout4.preferredMaxFrameRate == 60
                && GameDescriptor.fallout4.prefersNativeSessionDPI
                && GameDescriptor.fallout4.appliesAspectCorrectMouseLook
                && GameDescriptor.skyrimSE.preferredMaxFrameRate == nil
                && GameDescriptor.skyrimSE.prefersNativeSessionDPI
                && GameDescriptor.skyrimSE.usesScreenCoveringBorderlessSurface,
            "Fallout frame/mouse tuning stays title-scoped; Skyrim shares native fullscreen",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.sessionLogPixels(
                settings: fittingSettings,
                screenPixelWidth: 3420,
                prefersNative: true
            ) == 96,
            "native-DPI titles ignore the Retina session scale",
            passes: &passes,
            failures: &failures
        )
        let maximizedNativeSettings = GameProfileWriter.sessionSettings(
            fittingSettings,
            descriptor: .fallout4,
            logPixels: 96,
            screenPointWidth: 1710,
            screenPointHeight: 1107
        )
        expect(
            maximizedNativeSettings.width == 1710 && maximizedNativeSettings.height == 1107,
            "borderless native-DPI session renders at the point size it maximizes to",
            passes: &passes,
            failures: &failures
        )
        let maximizedSkyrimSettings = GameProfileWriter.sessionSettings(
            fittingSettings,
            descriptor: .skyrimSE,
            logPixels: 96,
            screenPointWidth: 1710,
            screenPointHeight: 1107
        )
        expect(
            maximizedSkyrimSettings.width == 1710
                && maximizedSkyrimSettings.height == 1107,
            "Skyrim borderless session covers the full display",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.sessionSettings(
                nativeSettings,
                descriptor: .insurgency,
                logPixels: 96,
                screenPointWidth: 1710,
                screenPointHeight: 1107,
                preservesRequestedResolution: true
            ) == nativeSettings,
            "backing-pixel profile writes the resolved engine dimensions exactly",
            passes: &passes,
            failures: &failures
        )
        var exclusiveSkyrimSettings = fittingSettings
        exclusiveSkyrimSettings.displayMode = .exclusiveFullscreen
        exclusiveSkyrimSettings.width = 1280
        exclusiveSkyrimSettings.height = 800
        let capturedSkyrimSettings = GameProfileWriter.sessionSettings(
            exclusiveSkyrimSettings,
            descriptor: .skyrimSE,
            logPixels: 96,
            screenPointWidth: 1710,
            screenPointHeight: 1107
        )
        expect(
            capturedSkyrimSettings == exclusiveSkyrimSettings,
            "Skyrim exclusive session keeps the player's validated switchable mode",
            passes: &passes,
            failures: &failures
        )
        let exclusiveFalloutSettings = exclusiveSkyrimSettings
        expect(
            GameProfileWriter.sessionSettings(
                exclusiveFalloutSettings,
                descriptor: .fallout4,
                logPixels: 96,
                screenPointWidth: 1710,
                screenPointHeight: 1107
            ) == exclusiveFalloutSettings,
            "captured exclusive mode does not alter other native-DPI games",
            passes: &passes,
            failures: &failures
        )
        var skyrimWindowedSettings = fittingSettings
        skyrimWindowedSettings.displayMode = .windowed
        expect(
            GameProfileWriter.sessionSettings(
                skyrimWindowedSettings,
                descriptor: .skyrimSE,
                logPixels: 96,
                screenPointWidth: 1710,
                screenPointHeight: 1107
            ) == skyrimWindowedSettings,
            "Skyrim windowed mode keeps the player's chosen resolution",
            passes: &passes,
            failures: &failures
        )
        var windowedNativeSettings = fittingSettings
        windowedNativeSettings.displayMode = .windowed
        expect(
            GameProfileWriter.sessionSettings(
                windowedNativeSettings,
                descriptor: .fallout4,
                logPixels: 96,
                screenPointWidth: 1710,
                screenPointHeight: 1107
            ) == windowedNativeSettings,
            "windowed native-DPI sessions keep the player's chosen resolution",
            passes: &passes,
            failures: &failures
        )
        let supcom2BorderlessSettings = GameProfileWriter.sessionSettings(
            fittingSettings,
            descriptor: .supcom2,
            logPixels: 96,
            screenPointWidth: 1710,
            screenPointHeight: 1107
        )
        expect(
            supcom2BorderlessSettings.width == 1710
                && supcom2BorderlessSettings.height == 1107,
            "Supreme Commander 2 borderless session covers the full display",
            passes: &passes,
            failures: &failures
        )
        var supcom2WindowedSettings = fittingSettings
        supcom2WindowedSettings.displayMode = .windowed
        expect(
            GameProfileWriter.sessionSettings(
                supcom2WindowedSettings,
                descriptor: .supcom2,
                logPixels: 96,
                screenPointWidth: 1710,
                screenPointHeight: 1107
            ) == supcom2WindowedSettings,
            "Supreme Commander 2 windowed mode keeps its requested size",
            passes: &passes,
            failures: &failures
        )
        let falloutControls = GameProfileWriter.mergingCustomIniValues(
            GameProfileWriter.resolvedCustomIniValues(
                settings: settings,
                descriptor: .fallout4
            ),
            into: "[General]\r\nsLanguage=ENGLISH\r\n"
        )
        expect(
            falloutControls.contains("[Controls]")
                && falloutControls.contains("bMouseAcceleration=0")
                && falloutControls.contains("bBackgroundMouse=1")
                && falloutControls.contains("fMouseHeadingXScale=0.021")
                && falloutControls.contains("fMouseHeadingYScale=0.03733")
                && falloutControls.contains("sLanguage=ENGLISH"),
            "Fallout 4 aspect-correct mouse look",
            passes: &passes,
            failures: &failures
        )

        let falloutProfile = GameProfileWriter.updatingDisplaySection(
            in: "[Display]\r\n",
            settings: settings,
            vsyncKey: GameDescriptor.fallout4.vsyncKey,
            usesMetalFramePacing: GameDescriptor.fallout4.usesMetalFramePacing
        )
        expect(falloutProfile.contains("iPresentInterval=0"), "Fallout Metal pacing disables game vsync", passes: &passes, failures: &failures)
        expect(falloutProfile.contains("bMaximizeWindow=1"), "Fallout borderless maximize", passes: &passes, failures: &failures)
        expect(!falloutProfile.contains("iVSyncPresentInterval"), "no Skyrim vsync key in Fallout profile", passes: &passes, failures: &failures)

        var qualitySettings = GameSettings()
        qualitySettings.quality = [
            "godrays": "Off",
            "ssao": "Off",
            "bogus-option": "On",
            "shadow-resolution": "Bogus Label"
        ]
        let falloutQuality = GameProfileWriter.qualityValues(
            settings: qualitySettings,
            descriptor: .fallout4
        )
        expect(
            falloutQuality["bVolumetricLightingEnable"] == "0"
                && falloutQuality["bSAOEnable"] == "0"
                && falloutQuality.count == 2,
            "quality choices resolve and stale entries drop",
            passes: &passes,
            failures: &failures
        )
        var godrayHigh = GameSettings()
        godrayHigh.quality = ["godrays": "High"]
        let falloutGodrays = GameProfileWriter.qualityValues(
            settings: godrayHigh,
            descriptor: .fallout4
        )
        expect(
            falloutGodrays["bVolumetricLightingEnable"] == "1"
                && falloutGodrays["iVolumetricLightingQuality"] == "2",
            "multi-key quality choice",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.qualityValues(settings: GameSettings(), descriptor: .skyrimSE).isEmpty,
            "default quality writes nothing",
            passes: &passes,
            failures: &failures
        )
        var skyrimShadowCompatibility = GameSettings()
        skyrimShadowCompatibility.quality = ["shadow-distance": "Off (compatibility)"]
        let skyrimShadowValues = GameProfileWriter.qualityValues(
            settings: skyrimShadowCompatibility,
            descriptor: .skyrimSE
        )
        expect(
            skyrimShadowValues == ["fShadowDistance": "0.0000"]
                && GameDescriptor.fallout4.qualityOption(for: "shadow-distance")?
                    .choices.contains(where: { $0.label == "Off (compatibility)" }) == false,
            "Skyrim-only zero-distance shadow workaround",
            passes: &passes,
            failures: &failures
        )

        expect(
            GameDescriptor.skyrimSE.documentsRelativePath == "My Games/Skyrim Special Edition"
                && GameDescriptor.supcom2.documentsRelativePath == "My Games/Gas Powered Games/Supreme Commander 2",
            "per-game documents paths",
            passes: &passes,
            failures: &failures
        )
        let luaSample = "options = {\n    UnitCap = 500,\n    other = 3,\n}\nlast = { UnitCap = 500 }\n"
        let luaUpdated = GameProfileWriter.updatingLuaNumericValue(
            in: luaSample,
            keyCandidates: ["unit_cap", "UnitCap"],
            value: "1000"
        )
        expect(
            luaUpdated.components(separatedBy: "UnitCap = 1000").count == 3
                && luaUpdated.contains("other = 3"),
            "lua unit cap rewrite covers every occurrence",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.updatingLuaNumericValue(
                in: "quoted = { unit_cap = '500' }",
                keyCandidates: ["unit_cap"],
                value: "750"
            ).contains("unit_cap = '750'"),
            "lua quoted value rewrite",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.updatingLuaNumericValue(
                in: luaSample,
                keyCandidates: ["missing_key"],
                value: "1000"
            ) == luaSample,
            "lua rewrite leaves unknown keys untouched",
            passes: &passes,
            failures: &failures
        )

        let legacySettings = try? JSONDecoder().decode(
            LauncherSettings.self,
            from: Data(#"{"launchInWindow":true,"width":1280,"height":800,"enableDiagnostics":false}"#.utf8)
        )
        let migrated = legacySettings?.game(.skyrimSE)
        expect(migrated?.displayMode == .windowed, "legacy windowed migration", passes: &passes, failures: &failures)
        expect(migrated?.width == 1280 && migrated?.height == 800, "legacy resolution migration", passes: &passes, failures: &failures)
        expect(migrated?.verticalSync == true, "legacy vsync default", passes: &passes, failures: &failures)
        expect(
            legacySettings?.game(.fallout4).fieldOfView == GameDescriptor.fallout4.defaultFieldOfView
                && legacySettings?.game(.fallout4).displayMode == .borderlessFullscreen,
            "unconfigured game gets descriptor defaults",
            passes: &passes,
            failures: &failures
        )
        let migratedFastSync = try? JSONDecoder().decode(
            LauncherSettings.self,
            from: Data(#"{"useFastSync":false,"games":{}}"#.utf8)
        )
        expect(
            migratedFastSync?.useFastSync == false
                && migratedFastSync?.activeFastSync == false,
            "legacy fast synchronization becomes the active mode",
            passes: &passes,
            failures: &failures
        )
        let queuedFastSync = try? JSONDecoder().decode(
            LauncherSettings.self,
            from: Data(#"{"useFastSync":false,"activeFastSync":true,"games":{}}"#.utf8)
        )
        expect(
            queuedFastSync?.useFastSync == false
                && queuedFastSync?.activeFastSync == true,
            "queued fast synchronization survives restart",
            passes: &passes,
            failures: &failures
        )

        let fingerprintBase = [
            "WINEDEBUG": "-all",
            "WINEMSYNC": "1",
            "PATH": "/runtime/bin:/usr/bin"
        ]
        expect(
            RuntimeManager.sessionFingerprint(environment: [:]) == "cbf29ce484222325"
                && RuntimeManager.sessionFingerprint(environment: fingerprintBase)
                    == RuntimeManager.sessionFingerprint(environment: fingerprintBase),
            "session fingerprint is stable",
            passes: &passes,
            failures: &failures
        )
        var fingerprintDebug = fingerprintBase
        fingerprintDebug["WINEDEBUG"] = "warn+all,err+all"
        var fingerprintExperiment = fingerprintBase
        fingerprintExperiment["WINE_HEAP_DELAY_FREE"] = "1"
        expect(
            RuntimeManager.sessionFingerprint(environment: fingerprintDebug)
                != RuntimeManager.sessionFingerprint(environment: fingerprintBase)
                && RuntimeManager.sessionFingerprint(environment: fingerprintExperiment)
                    != RuntimeManager.sessionFingerprint(environment: fingerprintBase),
            "session fingerprint tracks debug and experiment variables",
            passes: &passes,
            failures: &failures
        )
        var fingerprintStamped = fingerprintBase
        fingerprintStamped[RuntimeManager.sessionFingerprintKey] =
            RuntimeManager.sessionFingerprint(environment: fingerprintBase)
        expect(
            RuntimeManager.sessionFingerprint(environment: fingerprintStamped)
                == fingerprintStamped[RuntimeManager.sessionFingerprintKey],
            "stamped environment reproduces its own fingerprint",
            passes: &passes,
            failures: &failures
        )
        let sessionGeometry = HostDisplayGeometry(
            fullFramePoints: DisplayExtent(width: 1710, height: 1107),
            fullscreenContentPoints: DisplayExtent(width: 1710, height: 1074),
            visibleFramePoints: DisplayExtent(width: 1710, height: 1005),
            windowedContentPoints: DisplayExtent(width: 1710, height: 973),
            backingScale: 2,
            activeFullscreenModePoints: DisplayExtent(width: 1710, height: 1107),
            supportsTwoXRetina: true,
            switchableFullscreenModes: [DisplayExtent(width: 1710, height: 1107)]
        )
        let backingSessionContract = ResolvedGameDisplayContract(
            settings: nativeSettings,
            geometry: sessionGeometry,
            logPixels: 96,
            retinaMode: true,
            requiredFullscreenCoverage: nil
        )
        let backingSessionScope = GameService.displaySessionScope(
            descriptor: .insurgency,
            contract: backingSessionContract
        )
        var anotherResolutionContract = backingSessionContract
        anotherResolutionContract = ResolvedGameDisplayContract(
            settings: fittingSettings,
            geometry: anotherResolutionContract.geometry,
            logPixels: anotherResolutionContract.logPixels,
            retinaMode: anotherResolutionContract.retinaMode,
            requiredFullscreenCoverage: nil
        )
        let anotherResolutionScope = GameService.displaySessionScope(
            descriptor: .insurgency,
            contract: anotherResolutionContract
        )
        let pointSessionContract = ResolvedGameDisplayContract(
            settings: fittingSettings,
            geometry: sessionGeometry,
            logPixels: 96,
            retinaMode: false,
            requiredFullscreenCoverage: nil
        )
        let pointSessionScope = GameService.displaySessionScope(
            descriptor: .skyrimSE,
            contract: pointSessionContract
        )
        var backingEnvironment = fingerprintBase
        backingEnvironment["SECUNDA_DISPLAY_SESSION"] = backingSessionScope
        var pointEnvironment = fingerprintBase
        pointEnvironment["SECUNDA_DISPLAY_SESSION"] = pointSessionScope
        let backingFingerprint = RuntimeManager.sessionFingerprint(
            environment: backingEnvironment
        )
        let pointFingerprint = RuntimeManager.sessionFingerprint(
            environment: pointEnvironment
        )
        let sessionOnlyEnvironment = [
            "SECUNDA_DISPLAY_SESSION": backingSessionScope,
            RuntimeManager.sessionFingerprintKey: backingFingerprint
        ]
        let gameOnlyEnvironment = GameService.gameEnvironment(
            base: sessionOnlyEnvironment,
            descriptor: .insurgency
        )
        expect(
            backingSessionScope == anotherResolutionScope
                && backingSessionScope != pointSessionScope
                && backingFingerprint != pointFingerprint
                && GameService.sessionRequiresRestart(
                    live: pointFingerprint,
                    expected: backingFingerprint
                )
                && sessionOnlyEnvironment["SteamAppId"] == nil
                && gameOnlyEnvironment["SteamAppId"] == GameDescriptor.insurgency.steamAppID,
            "session stamps isolate process-latched display state, not resolution choices",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameService.sessionRequiresRestart(live: nil, expected: "abc")
                && GameService.sessionRequiresRestart(live: "other", expected: "abc")
                && !GameService.sessionRequiresRestart(live: "abc", expected: "abc")
                && !GameService.sessionRequiresRestart(live: nil, expected: nil),
            "unverifiable or foreign sessions restart, matching ones do not",
            passes: &passes,
            failures: &failures
        )
        let exactBottleProcess = BottleProcess(
            pid: 10,
            ppid: 1,
            command: "/Users/t/Bottles/Game/drive_c/game.exe"
        )
        let cloneBottleProcess = BottleProcess(
            pid: 11,
            ppid: 1,
            command: "/Users/t/Bottles/Game-Clone/drive_c/game.exe"
        )
        expect(
            BottleProcessInspector.belongsToBottle(
                exactBottleProcess,
                bottlePath: "/Users/t/Bottles/Game",
                environment: nil
            )
                && !BottleProcessInspector.belongsToBottle(
                    cloneBottleProcess,
                    bottlePath: "/Users/t/Bottles/Game",
                    environment: nil
                )
                && BottleProcessInspector.belongsToBottle(
                    BottleProcess(pid: 12, ppid: 1, command: "wineserver"),
                    bottlePath: "/Users/t/Bottles/Game",
                    environment: ["WINEPREFIX": "/Users/t/Bottles/Game"]
                )
                && !BottleProcessInspector.belongsToBottle(
                    BottleProcess(pid: 13, ppid: 1, command: "wineserver"),
                    bottlePath: "/Users/t/Bottles/Game",
                    environment: ["WINEPREFIX": "/Users/t/Bottles/Foreign"]
                ),
            "exact bottle ownership excludes sibling and foreign prefixes",
            passes: &passes,
            failures: &failures
        )
        var procArgs = Data()
        withUnsafeBytes(of: Int32(2).littleEndian) { procArgs.append(contentsOf: $0) }
        for chunk in [
            "/runtime/bin/wine\0\0\0", "wine\0", "C:\\games\\x=1.exe\0",
            "WINEDEBUG=-all\0", "\(RuntimeManager.sessionFingerprintKey)=abc123\0", "ptr_munge\0"
        ] {
            procArgs.append(contentsOf: [UInt8](chunk.utf8))
        }
        let parsedEnvironment = BottleProcessInspector.parseProcArgs2(procArgs)
        expect(
            parsedEnvironment?["WINEDEBUG"] == "-all"
                && parsedEnvironment?[RuntimeManager.sessionFingerprintKey] == "abc123"
                && parsedEnvironment?.count == 2
                && BottleProcessInspector.parseProcArgs2(Data([1, 0])) == nil,
            "KERN_PROCARGS2 parsing separates argv from environment",
            passes: &passes,
            failures: &failures
        )
        expect(
            BottleProcessInspector.isWineserver(
                BottleProcess(pid: 1, ppid: 1, command: "wineserver"),
                executablePath: "/runtime/bin/wineserver"
            )
                && !BottleProcessInspector.isWineserver(
                    BottleProcess(pid: 2, ppid: 1, command: "steam.exe"),
                    executablePath: "/bottle/drive_c/steam.exe"
                ),
            "wineserver identification",
            passes: &passes,
            failures: &failures
        )

        if failures.isEmpty {
            print("Secunda self-check: \(passes) contracts passed")
            return 0
        }

        for failure in failures {
            print("FAILED: \(failure)")
        }
        return 1
    }

    private static func expect(
        _ condition: Bool,
        _ name: String,
        passes: inout Int,
        failures: inout [String]
    ) {
        if condition {
            passes += 1
        } else {
            failures.append(name)
        }
    }
}
