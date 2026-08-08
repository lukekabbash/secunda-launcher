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
                .skyrimSE, .fallout4, .supcom2, .blackOps2SP, .blackOps2MP, .blackOps2Zombies
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
        // Every 32-bit Direct3D 9 title stays on the built-in path: DXVK's
        // 32-bit build cannot reach Vulkan through WoW64 in this runtime.
        expect(
            GameDescriptor.blackOps2SP.d3d9Backend == .wined3d
                && GameDescriptor.blackOps2MP.d3d9Backend == .wined3d
                && GameDescriptor.blackOps2Zombies.d3d9Backend == .wined3d
                && GameDescriptor.supcom2.d3d9Backend == .wined3d
                && GameDescriptor.skyrimSE.d3d9Backend == .wined3d,
            "per-game Direct3D 9 backends",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameGroup.all.count == 4
                && GameGroup.group(for: "black-ops-2")?.componentIDs
                    == ["bo2-campaign", "bo2-multiplayer", "bo2-zombies"]
                && GameGroup.group(for: "black-ops-2")?.isMultiComponent == true
                && GameGroup.group(for: "skyrim-se")?.isMultiComponent == false,
            "library groups unify Black Ops II",
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
        expect(
            GameDescriptor.blackOps2Zombies.modeTitle == "Zombies"
                && GameDescriptor.blackOps2MP.modeTitle == "Multiplayer"
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
                && GameDescriptor.fallout4.vsyncKey == "iPresentInterval",
            "per-game vsync keys",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.supcom2.executableRelativePath == "bin/SupremeCommander2.exe"
                && GameDescriptor.supcom2.gameImageName == "SupremeCommander2.exe"
                && !GameDescriptor.supcom2.supportsDisplayProfile
                && GameDescriptor.supcom2.usesWindowedResolutionArguments,
            "Supreme Commander 2 descriptor",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.supcom2.luaPrefsRelativePath
                == "AppData/Local/Gas Powered Games/Supreme Commander 2/Game.prefs",
            "Supreme Commander 2 prefs location",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameService.gameArguments(descriptor: .supcom2, settings: GameSettings())
                == ["/windowed", "1920", "1080"]
                && GameService.gameArguments(descriptor: .skyrimSE, settings: GameSettings()).isEmpty,
            "windowed resolution arguments",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameDescriptor.supcom2.luaTuningOptions.contains { $0.id == "fidelity-preset" }
                && GameDescriptor.supcom2.luaTuningOptions.contains { $0.id == "unit-cap" },
            "Supreme Commander 2 tuning options",
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
                bottlePath: "/Users/t/Bottles/SkyrimSE",
                executablePath: nil,
                runtimeRoot: "/opt/runtime"
            )
                && BottleProcessInspector.matches(
                    parsedProcesses[1],
                    bottlePath: "/Users/t/Bottles/SkyrimSE",
                    executablePath: "/opt/runtime/bin/wine64-preloader",
                    runtimeRoot: "/opt/runtime"
                )
                && !BottleProcessInspector.matches(
                    parsedProcesses[2],
                    bottlePath: "/Users/t/Bottles/SkyrimSE",
                    executablePath: "/usr/bin/unrelated",
                    runtimeRoot: "/opt/runtime"
                ),
            "game-space process matching by bottle path and runtime executable",
            passes: &passes,
            failures: &failures
        )
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
        expect(settings.fieldOfView == 95, "field of view default", passes: &passes, failures: &failures)
        expect(settings.nativeVoiceAudio, "voice audio default", passes: &passes, failures: &failures)
        expect(!launcherSettings.enableDiagnostics, "diagnostic defaults", passes: &passes, failures: &failures)
        expect(settings.width == 1920 && settings.height == 1080, "resolution defaults", passes: &passes, failures: &failures)
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
        expect(customProfile.contains("fDefaultWorldFOV=95"), "world FOV profile", passes: &passes, failures: &failures)
        expect(customProfile.contains("fDefault1stPersonFOV=95"), "first-person FOV profile", passes: &passes, failures: &failures)
        expect(customProfile.contains("sLanguage=ENGLISH"), "custom ini preservation", passes: &passes, failures: &failures)
        expect(
            GameDescriptor.fallout4.preferredMaxFrameRate == 60
                && GameDescriptor.fallout4.prefersNativeSessionDPI
                && GameDescriptor.fallout4.appliesAspectCorrectMouseLook
                && GameDescriptor.skyrimSE.preferredMaxFrameRate == nil
                && !GameDescriptor.skyrimSE.prefersNativeSessionDPI,
            "Fallout 4 mouse/frame fixes are Fallout-only",
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
            screenPixelWidth: 2880,
            screenPixelHeight: 1864
        )
        expect(
            maximizedNativeSettings.width == 2880 && maximizedNativeSettings.height == 1864,
            "borderless native-DPI session renders at the panel size it maximizes to",
            passes: &passes,
            failures: &failures
        )
        expect(
            GameProfileWriter.sessionSettings(
                fittingSettings,
                descriptor: .skyrimSE,
                logPixels: 216,
                screenPixelWidth: 2880,
                screenPixelHeight: 1864
            ) == fittingSettings,
            "Retina-scaled sessions keep the player's chosen resolution",
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
                screenPixelWidth: 2880,
                screenPixelHeight: 1864
            ) == windowedNativeSettings,
            "windowed native-DPI sessions keep the player's chosen resolution",
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
            legacySettings?.game(.fallout4) == GameSettings(),
            "unconfigured game gets defaults",
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
