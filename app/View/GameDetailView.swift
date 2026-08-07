import SwiftUI

struct GameDetailView: View {
    @ObservedObject var model: LauncherViewModel
    let descriptor: GameDescriptor

    @State private var showsCloseConfirmation = false
    @State private var showsUninstallConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero

                HStack(alignment: .top, spacing: 18) {
                    readiness
                    recentActivity
                }

                displaySettings
                dlcPanel
                savesPanel
            }
            .padding(.horizontal, 42)
            .padding(.bottom, 42)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            GameArtwork(url: descriptor.heroArtworkURL, fallbackSymbol: descriptor.symbol)
                .frame(height: 240)
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
                .clipShape(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .padding(.top, 24)

            Text(model.supportingText(for: descriptor))
                .font(.system(size: 15))
                .foregroundStyle(SecundaTheme.secondaryText)
                .lineSpacing(4)
                .frame(maxWidth: 590, alignment: .leading)

            HStack(spacing: 14) {
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
                    .buttonStyle(SecundaSecondaryButtonStyle())
                    .disabled(model.isBusy)
                    .help("Save first, then close every Windows app in this Secunda game space")
                }

                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .buttonStyle(SecundaSecondaryButtonStyle())
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
                            .frame(width: 18)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 6)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
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

    // MARK: - Status

    private var readiness: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Secunda setup", detail: "One separate installation")
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
        .secundaPanel()
        .frame(maxWidth: .infinity)
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Activity", detail: "Latest events")
            if model.activities.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quiet for now")
                        .font(.system(size: 13, weight: .medium))
                    Text("Setup and launch events will appear here.")
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            } else {
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
                }
            }
        }
        .secundaPanel()
        .frame(width: 300)
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
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: "Display & Audio", detail: "Applied at launch")

            HStack {
                Text("Mode")
                Spacer()
                Picker("Mode", selection: gameSetting(\.displayMode)) {
                    Text("Borderless Fullscreen").tag(DisplayMode.borderlessFullscreen)
                    Text("Exclusive Fullscreen").tag(DisplayMode.exclusiveFullscreen)
                    Text("Windowed").tag(DisplayMode.windowed)
                }
                .labelsHidden()
                .frame(width: 200)
            }
            Text(displayModeCaption)
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)

            HStack {
                Text("Resolution")
                Spacer()
                Picker("Resolution", selection: resolutionBinding) {
                    ForEach(resolutionOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }
            Text("Higher resolutions look sharper but cost frame rate. Your display's own sizes are listed first; native sizes run with exact 1:1 pixel mapping.")
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)

            HStack {
                Text("Field of view")
                Spacer()
                Stepper(
                    "\(model.gameSettings(for: descriptor).fieldOfView)°",
                    value: gameSetting(\.fieldOfView),
                    in: 70...110,
                    step: 5
                )
                .fixedSize()
            }
            Text("The game default is \(descriptor.defaultFieldOfView)°. Takes effect on the next game start.")
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)

            Toggle("Vertical sync", isOn: gameSetting(\.verticalSync))
            Text(model.gameSettings(for: descriptor).verticalSync
                ? "VSync caps the frame rate to your display for smooth, tear-free play."
                : "Uncapped frame rate can cause screen tearing and physics glitches in this engine.")
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)

            Toggle("Voice audio fix", isOn: gameSetting(\.nativeVoiceAudio))
            Text(model.gameSettings(for: descriptor).nativeVoiceAudio
                ? "Uses Microsoft’s freely redistributable XAudio so spoken dialogue is audible. Installed into the game space on first launch (~96 MB download)."
                : "Without the fix, spoken dialogue is silent on this engine because voice files use Windows Media compression.")
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)
        }
        .secundaPanel()
    }

    // MARK: - DLC

    private var dlcPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Add-ons", detail: "Managed through Steam")
            ForEach(model.dlcStates(for: descriptor)) { dlc in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: dlc.isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(dlc.isInstalled ? SecundaTheme.aurora : SecundaTheme.secondaryText)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
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
                    } else if dlc.descriptor.steamAppID != nil,
                              model.snapshot.game(descriptor).state.isReady {
                        Button("Install in Steam") {
                            model.requestDLCInstall(dlc.descriptor, for: descriptor)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.frost)
                    } else {
                        Text("Not detected")
                            .font(.caption)
                            .foregroundStyle(SecundaTheme.secondaryText)
                    }
                }
                .padding(.vertical, 3)
            }
            Text("Add-ons you own install through Steam’s own confirmation. Secunda only detects their files and never modifies your purchases.")
                .font(.caption2)
                .foregroundStyle(SecundaTheme.secondaryText)
        }
        .secundaPanel()
    }

    // MARK: - Saves

    private var savesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Saves", detail: "Local and reversible")
            HStack(spacing: 18) {
                MetricPanel(
                    value: "\(model.snapshot.game(descriptor).saveCount)",
                    label: "Local saves",
                    symbol: "doc.fill"
                )
                MetricPanel(
                    value: "\(model.snapshot.game(descriptor).backupCount)",
                    label: "Backups",
                    symbol: "shield.fill"
                )
            }
            Text(model.snapshot.game(descriptor).saveCount > 0
                 ? "Create a dated copy of every detected \(descriptor.shortTitle) save."
                 : "Saves will appear here after your first in-game save.")
                .font(.system(size: 13))
                .foregroundStyle(SecundaTheme.secondaryText)

            Button("Back Up Saves Now") {
                model.createSaveBackup(descriptor)
            }
            .buttonStyle(SecundaSecondaryButtonStyle())
            .disabled(model.snapshot.game(descriptor).saveCount == 0)
        }
        .secundaPanel()
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
