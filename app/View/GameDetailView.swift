import SwiftUI

struct GameDetailView: View {
    @ObservedObject var model: LauncherViewModel
    let descriptor: GameDescriptor

    @State private var showsCloseConfirmation = false
    @State private var showsUninstallConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                hero

                HStack(alignment: .top, spacing: 40) {
                    FlatSection(title: "Setup", detail: "One separate installation") {
                        VStack(alignment: .leading, spacing: 4) {
                            StatusRow(title: "This Mac", symbol: "desktopcomputer", state: model.snapshot.host)
                            StatusRow(title: "Secunda Engine", symbol: "shippingbox.fill", state: model.snapshot.runtime)
                            StatusRow(title: "Separate Windows Space", symbol: "cube.transparent", state: model.snapshot.bottle)
                            StatusRow(title: "Steam Client", symbol: "person.crop.circle", state: model.snapshot.steam)
                            StatusRow(
                                title: descriptor.shortTitle,
                                symbol: descriptor.symbol,
                                state: model.snapshot.game(descriptor).state
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)

                    FlatSection(title: "Activity", detail: "Latest events") {
                        activityList
                    }
                    .frame(width: 300)
                }

                FlatSection(title: "Display & Audio", detail: "Applied at launch") {
                    displaySettings
                }

                FlatSection(title: "Add-ons", detail: "Managed through Steam") {
                    dlcList
                }

                FlatSection(title: "Saves", detail: "Local and reversible") {
                    savesContent
                }
            }
            .padding(.horizontal, 42)
            .padding(.bottom, 48)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            GameArtwork(url: descriptor.heroArtworkURL, fallbackSymbol: descriptor.symbol)
                .frame(height: 250)
                .overlay {
                    LinearGradient(
                        colors: [.clear, SecundaTheme.void.opacity(0.55), SecundaTheme.void],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(descriptor.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2.4)
                            .foregroundStyle(SecundaTheme.frost)
                        Text(model.headline(for: descriptor))
                            .font(.system(size: 34, weight: .medium, design: .serif))
                            .tracking(-0.5)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.top, 24)

            Text(model.supportingText(for: descriptor))
                .font(.system(size: 15))
                .foregroundStyle(SecundaTheme.secondaryText)
                .lineSpacing(4)
                .frame(maxWidth: 590, alignment: .leading)

            HStack(spacing: 12) {
                Button {
                    model.performPrimaryAction(for: descriptor)
                } label: {
                    HStack(spacing: 10) {
                        if model.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: model.primaryAction(for: descriptor).symbol)
                        }
                        Text(model.primaryAction(for: descriptor).title(for: descriptor))
                    }
                    .frame(minWidth: 170)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                }
                .buttonStyle(SecundaPrimaryButtonStyle())
                .disabled(model.isBusy)

                if model.snapshot.steam.isReady {
                    Button {
                        showsCloseConfirmation = true
                    } label: {
                        Label("Close Apps", systemImage: "stop.fill")
                    }
                    .buttonStyle(SecundaActionButtonStyle())
                    .disabled(model.isBusy)
                    .help("Save first, then close every Windows app in this Secunda game space")
                }

                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecundaActionButtonStyle())
                .disabled(model.isBusy)

                if model.snapshot.game(descriptor).state.isReady {
                    Menu {
                        Button("Verify Game Files in Steam") {
                            model.verifyGameFiles(descriptor)
                        }
                        Divider()
                        Button("Uninstall through Steam…", role: .destructive) {
                            showsUninstallConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .buttonStyle(SecundaIconButtonStyle())
                    .disabled(model.isBusy)
                }
            }
            .padding(.top, 4)

            if let progress = model.setupProgress {
                SetupProgressRail(progress: progress)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !model.snapshot.game(descriptor).state.isReady {
                SetupJourneyRail(journey: model.setupJourney(for: descriptor))
                    .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: model.setupProgress)
        .confirmationDialog(
            "Close this Secunda game space?",
            isPresented: $showsCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close Games and Steam", role: .destructive) {
                model.stop()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Save your game first. This closes every Windows app in this Secunda game space.")
        }
        .confirmationDialog(
            "Uninstall \(descriptor.shortTitle)?",
            isPresented: $showsUninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("Ask Steam to Uninstall", role: .destructive) {
                model.requestGameUninstall(descriptor)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Steam removes the game files after you confirm in its window. Saves and settings stay in place.")
        }
    }

    // MARK: - Activity

    @ViewBuilder
    private var activityList: some View {
        if model.activities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quiet for now")
                    .font(.system(size: 13, weight: .medium))
                Text("Setup and launch events will appear here.")
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.activities.prefix(4)) { activity in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(activityColor(activity.kind))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activity.message)
                                .font(.system(size: 12))
                                .lineLimit(2)
                            Text(activity.date, style: .time)
                                .font(.caption2)
                                .foregroundStyle(SecundaTheme.secondaryText)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.activities)
        }
    }

    private func activityColor(_ kind: ActivityEntry.Kind) -> Color {
        switch kind {
        case .info: SecundaTheme.frost
        case .success: SecundaTheme.aurora
        case .warning: SecundaTheme.ember
        case .error: .red.opacity(0.8)
        }
    }

    // MARK: - Settings

    private var displaySettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            settingRow(
                label: "Mode",
                caption: displayModeCaption
            ) {
                Picker("Mode", selection: gameSetting(\.displayMode)) {
                    Text("Borderless Fullscreen").tag(DisplayMode.borderlessFullscreen)
                    Text("Exclusive Fullscreen").tag(DisplayMode.exclusiveFullscreen)
                    Text("Windowed").tag(DisplayMode.windowed)
                }
                .labelsHidden()
                .frame(width: 200)
            }

            settingRow(
                label: "Resolution",
                caption: "Higher looks sharper but costs frame rate. Your display's sizes are listed first; native sizes run with exact 1:1 pixel mapping."
            ) {
                Picker("Resolution", selection: resolutionBinding) {
                    ForEach(resolutionOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }

            settingRow(
                label: "Field of view",
                caption: "The game default is \(descriptor.defaultFieldOfView)°. Takes effect on the next game start."
            ) {
                Stepper(
                    "\(model.gameSettings(for: descriptor).fieldOfView)°",
                    value: gameSetting(\.fieldOfView),
                    in: 70...110,
                    step: 5
                )
                .fixedSize()
            }

            settingRow(
                label: "Vertical sync",
                caption: model.gameSettings(for: descriptor).verticalSync
                    ? "Caps the frame rate to your display for smooth, tear-free play."
                    : "Uncapped frame rate can cause screen tearing and physics glitches in this engine."
            ) {
                Toggle("Vertical sync", isOn: gameSetting(\.verticalSync))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            settingRow(
                label: "Voice audio fix",
                caption: model.gameSettings(for: descriptor).nativeVoiceAudio
                    ? "Uses Microsoft’s freely redistributable XAudio so spoken dialogue is audible. Installed into the game space on first launch."
                    : "Without the fix, spoken dialogue is silent because voice files use Windows Media compression."
            ) {
                Toggle("Voice audio fix", isOn: gameSetting(\.nativeVoiceAudio))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    private func settingRow<Control: View>(
        label: String,
        caption: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                control()
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    // MARK: - DLC

    private var dlcList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.dlcStates(for: descriptor)) { dlc in
                DLCRow(
                    dlc: dlc,
                    canInstall: dlc.descriptor.steamAppID != nil
                        && model.snapshot.game(descriptor).state.isReady
                ) {
                    model.requestDLCInstall(dlc.descriptor, for: descriptor)
                }
            }
            Text("Add-ons you own install through Steam’s own confirmation. Secunda only detects their files and never modifies your purchases.")
                .font(.caption2)
                .foregroundStyle(SecundaTheme.secondaryText)
                .padding(.top, 10)
        }
    }

    // MARK: - Saves

    private var savesContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 44) {
                stat(
                    value: model.snapshot.game(descriptor).saveCount,
                    label: "Local saves"
                )
                stat(
                    value: model.snapshot.game(descriptor).backupCount,
                    label: "Backups"
                )
                Spacer()
                Button {
                    model.createSaveBackup(descriptor)
                } label: {
                    Label("Back Up Saves Now", systemImage: "shield.lefthalf.filled")
                }
                .buttonStyle(SecundaActionButtonStyle())
                .disabled(model.snapshot.game(descriptor).saveCount == 0)
            }
            Text(model.snapshot.game(descriptor).saveCount > 0
                 ? "Backups are dated copies of every detected \(descriptor.shortTitle) save, kept outside the game space."
                 : "Saves will appear here after your first in-game save.")
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)
        }
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 30, weight: .medium, design: .serif))
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(SecundaTheme.secondaryText)
        }
    }

    // MARK: - Bindings

    private func gameSetting<T>(_ keyPath: WritableKeyPath<GameSettings, T>) -> Binding<T> {
        Binding(
            get: { model.gameSettings(for: descriptor)[keyPath: keyPath] },
            set: { newValue in
                var updated = model.gameSettings(for: descriptor)
                updated[keyPath: keyPath] = newValue
                model.updateGameSettings(updated, for: descriptor)
            }
        )
    }

    private var resolutionBinding: Binding<String> {
        Binding(
            get: {
                let settings = model.gameSettings(for: descriptor)
                return "\(settings.width)x\(settings.height)"
            },
            set: { value in
                let parts = value.split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2 else { return }
                var updated = model.gameSettings(for: descriptor)
                updated.width = parts[0]
                updated.height = parts[1]
                model.updateGameSettings(updated, for: descriptor)
            }
        )
    }

    private var displayModeCaption: String {
        switch model.gameSettings(for: descriptor).displayMode {
        case .borderlessFullscreen:
            return "Fills the screen as a borderless window, so switching apps with Cmd-Tab works reliably. Recommended."
        case .exclusiveFullscreen:
            return "Classic fullscreen. Switching away can leave the game unable to regain the screen; use only if borderless causes problems."
        case .windowed:
            return "A regular window at the selected resolution. Useful for setup and troubleshooting."
        }
    }

    private struct ResolutionOption: Identifiable {
        let width: Int
        let height: Int
        let note: String?

        var id: String { "\(width)x\(height)" }
        var label: String {
            let base = "\(width) × \(height)"
            return note.map { "\(base)  (\($0))" } ?? base
        }
    }

    /// The main display's sizes first, then common Mac panel resolutions,
    /// then whatever custom value is already saved so the picker never
    /// shows an empty selection.
    private var resolutionOptions: [ResolutionOption] {
        var options: [ResolutionOption] = []
        var seen = Set<String>()

        func add(_ width: Int, _ height: Int, note: String? = nil) {
            guard width > 0, height > 0 else { return }
            let option = ResolutionOption(width: width, height: height, note: note)
            guard seen.insert(option.id).inserted else { return }
            options.append(option)
        }

        if let screen = NSScreen.main {
            let points = screen.frame.size
            let scale = screen.backingScaleFactor
            add(Int(points.width * scale), Int(points.height * scale), note: "this display, native")
            add(Int(points.width), Int(points.height), note: "this display")
        }
        for (width, height) in [
            (3456, 2234), (3024, 1964), (2880, 1864), (2560, 1664),
            (2560, 1440), (1920, 1200), (1920, 1080), (1728, 1117),
            (1512, 982), (1470, 956), (1440, 900), (1280, 800)
        ] {
            add(width, height)
        }
        let current = model.gameSettings(for: descriptor)
        add(current.width, current.height)
        return options
    }
}

/// One add-on row with a full-width hover state and a real install button.
private struct DLCRow: View {
    let dlc: DLCState
    let canInstall: Bool
    let install: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: dlc.isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(dlc.isInstalled ? SecundaTheme.aurora : SecundaTheme.secondaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text(dlc.descriptor.title)
                    .font(.system(size: 13, weight: .medium))
                if let note = dlc.descriptor.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)
                }
            }
            Spacer()
            if dlc.isInstalled {
                Text("Installed")
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.aurora)
            } else if canInstall {
                Button("Install in Steam", action: install)
                    .buttonStyle(SecundaActionButtonStyle())
                    .opacity(isHovering ? 1 : 0.75)
            } else {
                Text("Not detected")
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.045 : 0))
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
    }
}
