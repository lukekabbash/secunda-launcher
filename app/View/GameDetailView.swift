import SwiftUI

struct GameDetailView: View {
    @ObservedObject var model: LauncherViewModel
    let group: GameGroup

    @State private var showsCloseConfirmation = false
    @State private var showsUninstallConfirmation = false
    @State private var showsManageSheet = false
    @State private var contentAppeared = false
    @State private var selectedComponentID: String?

    /// The component every section of this page acts on. For single-game
    /// groups this is just the game; for multi-component entries it follows
    /// the mode picker and persists as the group default.
    private var descriptor: GameDescriptor {
        if let id = selectedComponentID,
           group.componentIDs.contains(id),
           let selected = GameDescriptor.descriptor(for: id) {
            return selected
        }
        return model.defaultComponent(for: group)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroBanner

                VStack(alignment: .leading, spacing: 40) {
                    heroActions

                    FlatSection(title: "Status", detail: statusSectionDetail) {
                        VStack(alignment: .leading, spacing: 16) {
                            StatusStrip(items: [
                                .init(title: "This Mac", state: model.snapshot.host),
                                .init(title: "Compatibility Runtime", state: model.snapshot.runtime),
                                .init(title: "Game Space", state: model.snapshot.bottle),
                                .init(title: "Steam Client", state: model.snapshot.steam),
                                .init(title: descriptor.shortTitle, state: model.snapshot.game(descriptor).state)
                            ])
                            activityList
                        }
                    }

                // Every game shows the same four sections in the same order.
                // Titles that have nothing to offer say so plainly rather
                // than leaving a hole in the layout.
                FlatSection(title: "Display", detail: displaySectionDetail) {
                    if descriptor.managedDisplayCapabilities.hasAny
                        || !descriptor.launchProfile.options.isEmpty
                        || descriptor.usesNativeVoiceAudioFix {
                        displaySettings
                    } else {
                        emptyNote("\(descriptor.shortTitle) manages its own display and audio options. Set resolution and windowed mode inside the game's settings menu.")
                    }
                }

                FlatSection(title: "Graphics", detail: graphicsSectionDetail) {
                    if !descriptor.qualityOptions.isEmpty || !descriptor.luaTuningOptions.isEmpty {
                        VStack(alignment: .leading, spacing: 28) {
                            if !descriptor.qualityOptions.isEmpty { qualitySettings }
                            if !descriptor.luaTuningOptions.isEmpty { tuningSettings }
                        }
                    } else {
                        emptyNote("Secunda has no tested graphics overrides for \(descriptor.shortTitle) yet. Use the game's own video options.")
                    }
                }

                FlatSection(title: "Add-ons", detail: descriptor.dlc.isEmpty ? "None" : "Managed through Steam") {
                    if descriptor.dlc.isEmpty {
                        emptyNote("\(descriptor.shortTitle) has no add-ons Secunda tracks. Anything you own still installs through Steam as usual.")
                    } else {
                        dlcList
                    }
                }

                FlatSection(title: "Saves", detail: descriptor.saveFileExtensions.isEmpty ? "None detected" : "Local and reversible") {
                    if descriptor.saveFileExtensions.isEmpty {
                        emptyNote("Secunda does not currently detect or back up \(descriptor.shortTitle) saves.")
                    } else {
                        savesContent
                    }
                }
                }
                .padding(.horizontal, 42)
                .padding(.top, 26)
                .padding(.bottom, 48)
                .frame(maxWidth: 980, alignment: .leading)
                // Column floats centered in the pane, Claude-style; text
                // inside stays left-aligned.
                .frame(maxWidth: .infinity)
                // Body settles a beat after the banner, which the page
                // transition has already brought in.
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 8)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            selectedComponentID = model.defaultComponent(for: group).id
            withAnimation(.easeOut(duration: 0.3).delay(0.06)) {
                contentAppeared = true
            }
        }
        .sheet(isPresented: $showsManageSheet) {
            ManageInstallSheet(model: model, group: group) {
                showsManageSheet = false
            }
        }
    }

    private var modeBinding: Binding<String> {
        Binding(
            get: { descriptor.id },
            set: { newID in
                selectedComponentID = newID
                if let component = GameDescriptor.descriptor(for: newID) {
                    model.setDefaultComponent(component, for: group)
                }
            }
        )
    }

    // MARK: - Hero

    /// Full-bleed banner: the artwork spans the whole pane and dissolves
    /// into the night background on every edge.
    private var heroBanner: some View {
        GameArtwork(
            candidates: model.artworkCandidates(for: descriptor, hero: true),
            fallbackSymbol: descriptor.symbol,
            cropsToFill: true
        )
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: SecundaTheme.void.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.28),
                        .init(color: SecundaTheme.void.opacity(0.35), location: 0.72),
                        .init(color: SecundaTheme.void, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: SecundaTheme.void.opacity(0.9), location: 0),
                        .init(color: .clear, location: 0.22),
                        .init(color: .clear, location: 0.78),
                        .init(color: SecundaTheme.void.opacity(0.9), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .overlay(alignment: .bottom) {
                // Constrained to the same 980pt column as the body so the
                // headline lines up with the centered content below it.
                VStack(alignment: .leading, spacing: 7) {
                    Text(descriptor.title.uppercased())
                        .font(.system(size: SecundaTheme.FontSize.small, weight: .semibold))
                        .tracking(2.4)
                        .foregroundStyle(SecundaTheme.frost)
                    Text(secundaRuntimeTerminology(heroHeadline))
                        .font(.system(size: SecundaTheme.FontSize.hero, weight: .medium, design: .serif))
                        .tracking(-0.5)
                        .shadow(color: .black.opacity(0.55), radius: 10, y: 2)
                    Text(descriptor.tagline)
                        .font(.system(size: SecundaTheme.FontSize.body, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(SecundaTheme.secondaryText)
                }
                .padding(.horizontal, 42)
                .padding(.bottom, 20)
                .frame(maxWidth: 980, alignment: .bottomLeading)
            }
            .clipped()
    }

    private var heroActions: some View {
        VStack(alignment: .leading, spacing: 18) {
            if group.isMultiComponent {
                HStack(spacing: 12) {
                    SecundaSegmentedPicker(
                        selection: modeBinding,
                        options: group.components.map { ($0.id, $0.modeTitle) }
                    )

                    Button {
                        showsManageSheet = true
                    } label: {
                        Label("Edit Installation", systemImage: "square.and.arrow.down.on.square")
                    }
                    .buttonStyle(SecundaActionButtonStyle())
                    .disabled(model.isBusy || !model.snapshot.steam.isReady)
                }
            }

            Text(secundaRuntimeTerminology(heroSupportingText))
                .font(.system(size: SecundaTheme.FontSize.lead))
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
                    .frame(minWidth: 150)
                }
                .buttonStyle(SecundaActionButtonStyle(prominent: true))
                .disabled(model.isBusy || launchBlockedByOtherGroup)
                .help(launchBlockedByOtherGroup
                    ? "Close the running game before starting another one."
                    : model.primaryAction(for: descriptor).title(for: descriptor))

                if model.isGroupRunning(group) {
                    Button {
                        showsCloseConfirmation = true
                    } label: {
                        Label("Stop \(group.shortTitle)", systemImage: "stop.fill")
                    }
                    .buttonStyle(SecundaDestructiveButtonStyle())
                    .disabled(model.isBusy)
                    .help("Save first — this closes \(group.shortTitle) and every Windows app in this game space")
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
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
                SetupRail(
                    title: progress.title,
                    label: progress.stepLabel,
                    detail: progress.detail,
                    fraction: progress.fraction
                )
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if !model.snapshot.game(descriptor).state.isReady {
                let journey = model.setupJourney(for: descriptor)
                SetupRail(
                    title: journey.title,
                    label: journey.label,
                    detail: journey.detail,
                    fraction: journey.fraction,
                    tint: SecundaTheme.aurora,
                    isActive: false
                )
                .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: model.setupProgress)
        .animation(.easeOut(duration: 0.22), value: model.isGameRunning(descriptor))
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
            Text("Save your game first. This closes every Windows app in this game space.")
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

    private var launchBlockedByOtherGroup: Bool {
        model.primaryAction(for: descriptor) == .play
            && model.anyGameRunning
            && !model.isGroupRunning(group)
    }

    private var heroHeadline: String {
        if model.isGroupRunning(group), model.runningComponent(in: group) == nil {
            return "A \(group.shortTitle) session is running."
        }
        return model.headline(for: descriptor)
    }

    private var heroSupportingText: String {
        if model.isGroupRunning(group), model.runningComponent(in: group) == nil {
            return "Secunda can see this session but cannot tell which mode is running after a restart. Save and quit in the game; Stop closes the shared game space."
        }
        if launchBlockedByOtherGroup {
            return "Another game is using the shared game space. Close it before starting \(descriptor.shortTitle)."
        }
        return model.supportingText(for: descriptor)
    }

    // MARK: - Activity

    /// Latest events as compact one-liners under the status strip.
    @ViewBuilder
    private var activityList: some View {
        if model.activities.isEmpty {
            Text("Setup and launch events will appear here.")
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(model.activities.prefix(3)) { activity in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(activityColor(activity.kind))
                            .frame(width: 5, height: 5)
                        Text(secundaRuntimeTerminology(activity.message))
                            .font(.caption)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Text(activity.date, style: .time)
                            .font(.caption2)
                            .foregroundStyle(SecundaTheme.secondaryText)
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
        case .error: SecundaTheme.danger
        }
    }

    // MARK: - Settings

    private var displaySettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !descriptor.managedINIProfiles.isEmpty,
               !model.managedINIProfilesDetected(for: descriptor) {
                Text("Saved here now. After a successful first run creates the live settings files, Secunda applies these choices on the next launch. It never edits the shipped Default INIs.")
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.ember)
                    .frame(maxWidth: 560, alignment: .leading)
            }

            if !descriptor.supportedDisplayModes.isEmpty {
                settingRow(
                    label: "Mode",
                    caption: displayModeCaption
                ) {
                    Picker("Mode", selection: displayModeBinding) {
                        ForEach(descriptor.supportedDisplayModes, id: \.self) { mode in
                            Text(displayModeTitle(mode)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if descriptor.managedDisplayCapabilities.resolution {
                settingRow(
                    label: "Resolution",
                    caption: resolutionCaption
                ) {
                    Picker("Resolution", selection: resolutionBinding) {
                        ForEach(resolutionOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .disabled(resolutionFollowsDesktop)
                }
            }

            if descriptor.managedDisplayCapabilities.fieldOfView {
                settingRow(
                    label: "Field of view",
                    caption: "The game default is \(descriptor.defaultFieldOfView)°. Takes effect the next time the game starts."
                ) {
                    Stepper(
                        "\(model.gameSettings(for: descriptor).fieldOfView)°",
                        value: gameSetting(\.fieldOfView),
                        in: descriptor.managedFieldOfViewRange,
                        step: 5
                    )
                    .fixedSize()
                }
            }

            if descriptor.managedDisplayCapabilities.verticalSync,
               let frameRate = descriptor.preferredMaxFrameRate {
                settingRow(
                    label: "Frame pacing",
                    caption: "Locked to \(frameRate) fps so camera look stays stable. The game’s own vsync stays off so the two waits do not stack."
                ) {
                    Text("\(frameRate) fps")
                        .font(.body.weight(.medium))
                        .foregroundStyle(SecundaTheme.secondaryText)
                }
            } else if descriptor.managedDisplayCapabilities.verticalSync {
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
            }

            ForEach(descriptor.launchProfile.options) { option in
                settingRow(label: option.title, caption: option.caption) {
                    Picker(option.title, selection: launchOptionBinding(option)) {
                        ForEach(option.choices, id: \.label) { choice in
                            Text(choice.label).tag(choice.label)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if descriptor.usesNativeVoiceAudioFix {
                settingRow(
                    label: "Voice audio fix",
                    caption: model.gameSettings(for: descriptor).nativeVoiceAudio
                        ? "Uses Microsoft’s freely redistributable audio components so spoken dialogue is audible. Installed into the game space on first launch."
                        : "Without the fix, spoken dialogue is silent because voice files use Windows Media compression."
                ) {
                    Toggle("Voice audio fix", isOn: gameSetting(\.nativeVoiceAudio))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var qualitySettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("“Game default” leaves the game’s own choice untouched. Every other choice updates an existing live setting at launch.")
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)
                .frame(maxWidth: 560, alignment: .leading)

            ForEach(descriptor.qualityOptions) { option in
                settingRow(
                    label: option.title,
                    caption: option.caption ?? ""
                ) {
                    Picker(option.title, selection: qualityBinding(option)) {
                        ForEach(option.choices, id: \.label) { choice in
                            Text(choice.label).tag(choice.label)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var tuningSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !model.luaPrefsDetected(for: descriptor) {
                Text("These apply to the game's own settings file, which \(descriptor.shortTitle) creates the first time it runs. Launch the game once, quit, and Secunda takes over from there.")
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.ember)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            ForEach(descriptor.luaTuningOptions) { option in
                settingRow(
                    label: option.title,
                    caption: option.caption ?? ""
                ) {
                    Picker(option.title, selection: tuningBinding(option)) {
                        ForEach(option.choices, id: \.label) { choice in
                            Text(choice.label).tag(choice.label)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            Text("Secunda only rewrites values the game has already saved. It never invents settings, so a mistuned entry cannot corrupt the file.")
                .font(.caption2)
                .foregroundStyle(SecundaTheme.secondaryText)
        }
    }

    private func tuningBinding(_ option: LuaTuningOption) -> Binding<String> {
        Binding(
            get: {
                model.gameSettings(for: descriptor).tuning[option.id]
                    ?? QualityOption.gameDefaultLabel
            },
            set: { newLabel in
                var updated = model.gameSettings(for: descriptor)
                if newLabel == QualityOption.gameDefaultLabel {
                    updated.tuning.removeValue(forKey: option.id)
                } else {
                    updated.tuning[option.id] = newLabel
                }
                model.updateGameSettings(updated, for: descriptor)
            }
        )
    }

    private func qualityBinding(_ option: QualityOption) -> Binding<String> {
        Binding(
            get: {
                model.gameSettings(for: descriptor).quality[option.id]
                    ?? QualityOption.gameDefaultLabel
            },
            set: { newLabel in
                var updated = model.gameSettings(for: descriptor)
                if newLabel == QualityOption.gameDefaultLabel {
                    updated.quality.removeValue(forKey: option.id)
                } else {
                    updated.quality[option.id] = newLabel
                }
                model.updateGameSettings(updated, for: descriptor)
            }
        )
    }

    private func launchOptionBinding(_ option: LaunchOption) -> Binding<String> {
        Binding(
            get: {
                model.gameSettings(for: descriptor).tuning[option.id]
                    ?? QualityOption.gameDefaultLabel
            },
            set: { newLabel in
                var updated = model.gameSettings(for: descriptor)
                if newLabel == QualityOption.gameDefaultLabel {
                    updated.tuning.removeValue(forKey: option.id)
                } else {
                    updated.tuning[option.id] = newLabel
                }
                model.updateGameSettings(updated, for: descriptor)
            }
        )
    }

    /// Uniform control column: every setting's control occupies the same
    /// trailing width, so rows line up across all games and sections.
    private static let controlWidth: CGFloat = 230

    private var displaySectionDetail: String {
        if !descriptor.managedINIProfiles.isEmpty {
            return model.managedINIProfilesDetected(for: descriptor)
                ? "Live settings detected"
                : "Awaiting first run"
        }
        return descriptor.managedDisplayCapabilities.hasAny
            || !descriptor.launchProfile.options.isEmpty
            ? "Applied at launch"
            : "In-game"
    }

    private var statusSectionDetail: String {
        group.isMultiComponent
            ? "Each component installs separately"
            : "One separate installation"
    }

    private var graphicsSectionDetail: String {
        if !descriptor.managedINIProfiles.isEmpty,
           !descriptor.qualityOptions.isEmpty {
            return model.managedINIProfilesDetected(for: descriptor)
                ? "Live settings detected"
                : "Awaiting first run"
        }
        if !descriptor.qualityOptions.isEmpty {
            return "Applied at launch"
        }
        if !descriptor.luaTuningOptions.isEmpty {
            return model.luaPrefsDetected(for: descriptor)
                ? "Live settings detected"
                : "Awaiting first run"
        }
        return "In-game"
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(SecundaTheme.secondaryText)
            .lineSpacing(3)
            .frame(maxWidth: 560, alignment: .leading)
    }

    private func settingRow<Control: View>(
        label: String,
        caption: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label)
                    .font(.system(size: SecundaTheme.FontSize.body, weight: .medium))
                Spacer()
                control()
                    .frame(width: Self.controlWidth, alignment: .trailing)
            }
            if !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.secondaryText)
                    .frame(maxWidth: 560, alignment: .leading)
            }
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
                 : "Saves appear here after your first in-game save.")
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)
        }
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: SecundaTheme.FontSize.display, weight: .medium, design: .serif))
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(size: SecundaTheme.FontSize.micro, weight: .semibold))
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

    private var displayModeBinding: Binding<DisplayMode> {
        Binding(
            get: { model.gameSettings(for: descriptor).displayMode },
            set: { mode in
                var updated = model.gameSettings(for: descriptor)
                updated.displayMode = mode
                if mode == .exclusiveFullscreen,
                   descriptor.launchProfile.displayCoordinatePolicy != .backingPixels,
                   descriptor.launchProfile.exclusiveFullscreenPolicy == .capturedHostMode {
                    let hostModes = resolvedHostDisplayModes
                    let requested = DisplayExtent(width: updated.width, height: updated.height)
                    if !hostModes.switchable.contains(requested),
                       let fallback = hostModes.active ?? hostModes.switchable.first {
                        updated.width = fallback.width
                        updated.height = fallback.height
                    }
                }
                model.updateGameSettings(updated, for: descriptor)
            }
        )
    }

    private var resolutionBinding: Binding<String> {
        Binding(
            get: {
                if let fixed = borderlessDesktopResolution {
                    return fixed.id
                }
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
            if resolutionFollowsDesktop {
                return "Fills the screen at the desktop resolution. Switching apps with Cmd-Tab remains reliable."
            }
            return "Fills the screen as a borderless window, so switching apps with Cmd-Tab works reliably. Recommended."
        case .exclusiveFullscreen:
            if descriptor.launchProfile.exclusiveFullscreenPolicy == .capturedHostMode {
                return "Uses a display mode this Mac can switch to. Choose the render resolution below."
            }
            if descriptor.launchProfile.exclusiveModeUsesGameDefault {
                return "Uses the game's default display behavior while still applying the selected resolution."
            }
            return "Classic fullscreen. Switching away can leave the game unable to regain the screen; use only if borderless causes problems."
        case .windowed:
            return "A regular window at the selected resolution. Useful for setup and troubleshooting."
        }
    }

    private func displayModeTitle(_ mode: DisplayMode) -> String {
        switch mode {
        case .borderlessFullscreen: "Borderless Fullscreen"
        case .exclusiveFullscreen:
            descriptor.launchProfile.exclusiveModeUsesGameDefault
                ? "Game Default / Fullscreen"
                : "Exclusive Fullscreen"
        case .windowed: "Windowed"
        }
    }

    private var resolutionOptions: [DisplayResolutionOption] {
        if let fixed = borderlessDesktopResolution {
            return [fixed]
        }
        let screen = displayScreen
        let size = screen?.frame.size ?? .zero
        let current = model.gameSettings(for: descriptor)
        if current.displayMode == .exclusiveFullscreen,
           descriptor.launchProfile.exclusiveFullscreenPolicy == .capturedHostMode {
            let hostModes = resolvedHostDisplayModes
            var options = DisplayResolutionCatalog.capturedExclusiveOptions(
                modes: hostModes.switchable,
                active: hostModes.active
            )
            let currentID = "\(current.width)x\(current.height)"
            if descriptor.launchProfile.displayCoordinatePolicy == .backingPixels,
               !options.contains(where: { $0.id == currentID }) {
                options.append(DisplayResolutionOption(
                    width: current.width,
                    height: current.height,
                    note: "Unavailable on This Display"
                ))
            }
            return options
        }
        if descriptor.launchProfile.displayCoordinatePolicy == .backingPixels {
            let pixels = resolvedHostDisplayModes.activePixels
                ?? DisplayExtent(
                    width: Int((size.width * (screen?.backingScaleFactor ?? 1)).rounded()),
                    height: Int((size.height * (screen?.backingScaleFactor ?? 1)).rounded())
                )
            return DisplayResolutionCatalog.options(
                screenWidth: pixels.width,
                screenHeight: pixels.height,
                currentWidth: current.width,
                currentHeight: current.height
            )
        }
        return DisplayResolutionCatalog.options(
            screenWidth: Int(size.width),
            screenHeight: Int(size.height),
            currentWidth: current.width,
            currentHeight: current.height,
            screenPixelWidth: screen.map { Int(($0.frame.width * $0.backingScaleFactor).rounded()) },
            screenPixelHeight: screen.map { Int(($0.frame.height * $0.backingScaleFactor).rounded()) }
        )
    }

    private var resolutionCaption: String {
        let settings = model.gameSettings(for: descriptor)
        if resolutionFollowsDesktop {
            return "Borderless follows the current desktop pixels. Choose Exclusive for a real lower display mode or Windowed for an exact custom client size."
        }
        if settings.displayMode == .exclusiveFullscreen,
           descriptor.launchProfile.exclusiveFullscreenPolicy == .capturedHostMode {
            return "Exclusive fullscreen lists the display modes this Mac can switch to. The current mode is marked. Lower switchable modes stay available."
        }
        let nativePixelNote = "Native Pixels is the panel’s physical resolution. 4K UHD stays available for 3840 × 2160 displays."
        if descriptor.launchProfile.usesTransitionSafeBorderlessSurface {
            return nativePixelNote + " Borderless uses one safe aspect for fullscreen and windowed transitions; windowed sizes fit the visible desktop without stretching."
        }
        return nativePixelNote + " Profiles that support fitting keep oversized windows inside the desktop without stretching."
    }

    private var displayScreen: NSScreen? {
        descriptor.launchProfile.displayCoordinatePolicy == .backingPixels
            ? HostDisplayModeCatalog.wineMainScreen()
            : NSScreen.main
    }

    private var resolvedHostDisplayModes: HostDisplayModes {
        let modes = HostDisplayModeCatalog.modes(for: displayScreen)
        let retinaMode = descriptor.launchProfile.displayCoordinatePolicy == .backingPixels
            && modes.supportsTwoXRetina
        return modes.wineCoordinates(retinaMode: retinaMode)
    }

    private var resolutionFollowsDesktop: Bool {
        descriptor.launchProfile.displayCoordinatePolicy == .backingPixels
            && model.gameSettings(for: descriptor).displayMode == .borderlessFullscreen
    }

    private var borderlessDesktopResolution: DisplayResolutionOption? {
        guard resolutionFollowsDesktop,
              let active = resolvedHostDisplayModes.active
        else { return nil }
        return DisplayResolutionOption(
            width: active.width,
            height: active.height,
            note: "Current Desktop Pixels"
        )
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
                    .font(.system(size: SecundaTheme.FontSize.body, weight: .medium))
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
            RoundedRectangle(cornerRadius: SecundaTheme.Radius.md, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.045 : 0))
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
    }
}
