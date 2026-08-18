import SwiftUI

struct GamesGridView: View {
    @ObservedObject var model: LauncherViewModel
    @State private var appeared = false
    @State private var launchSheetGroup: GameGroup?
    @State private var manageSheetGroup: GameGroup?
    @State private var stopConfirmationGroup: GameGroup?

    private let columns = [
        GridItem(.adaptive(minimum: 216, maximum: 280), spacing: 28)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                PageHeader(
                    eyebrow: "LIBRARY",
                    title: "Your games.",
                    detail: "Play Windows Steam games you already own. A game space is the private Windows environment Secunda uses for Steam and your library. Skyrim, Fallout 4, Supreme Commander 2, and Insurgency are proven on Apple silicon; other listed titles may not work."
                )

                gameSection(title: "INSTALLED", groups: installedGroups, indexOffset: 0)
                gameSection(
                    title: "UNINSTALLED",
                    groups: uninstalledGroups,
                    indexOffset: installedGroups.count
                )
            }
            .padding(42)
            .frame(maxWidth: 1120, alignment: .leading)
            // Column floats centered in the pane; content stays left-aligned.
            .frame(maxWidth: .infinity)
        }
        .onAppear { appeared = true }
        .sheet(item: $launchSheetGroup) { group in
            LaunchModeSheet(model: model, group: group) {
                launchSheetGroup = nil
            }
        }
        .sheet(item: $manageSheetGroup) { group in
            ManageInstallSheet(model: model, group: group) {
                manageSheetGroup = nil
            }
        }
        .confirmationDialog(
            "Close this Secunda game space?",
            isPresented: Binding(
                get: { stopConfirmationGroup != nil },
                set: { if !$0 { stopConfirmationGroup = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Close Games and Steam", role: .destructive) {
                model.stopActiveGameSpace()
                stopConfirmationGroup = nil
            }
            Button("Cancel", role: .cancel) { stopConfirmationGroup = nil }
        } message: {
            Text("Save first when possible. This closes the active game and every Windows app in the shared game space.")
        }
    }

    private var installedGroups: [GameGroup] {
        GameGroup.all.filter { model.anyComponentInstalled(in: $0) }
    }

    private var uninstalledGroups: [GameGroup] {
        GameGroup.all.filter { !model.anyComponentInstalled(in: $0) }
    }

    @ViewBuilder
    private func gameSection(title: String, groups: [GameGroup], indexOffset: Int) -> some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(size: SecundaTheme.FontSize.micro, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(SecundaTheme.secondaryText)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        gameCard(group, animationIndex: index + indexOffset)
                    }
                }
            }
        }
    }

    private func gameCard(_ group: GameGroup, animationIndex: Int) -> some View {
        let component = model.defaultComponent(for: group)
        let primaryAction = groupPrimaryAction(group, defaultComponent: component)
        let isActive = model.isGroupActive(group)
        let isLocked = model.anyGameActive && !isActive
        return GameCard(
            descriptor: component,
            artwork: model.artworkCandidates(for: group.artworkComponent ?? component, hero: false),
            displayTitle: group.shortTitle,
            accessibilityTitle: group.title,
            state: groupCardState(group),
            statusOverride: groupStatus(group),
            isActive: isActive,
            isLocked: isLocked,
            primaryAction: primaryAction,
            quickActionSymbol: isActive ? "stop.fill" : primaryAction.symbol,
            quickActionTitle: isActive
                ? "Stop \(group.shortTitle)"
                : groupQuickActionTitle(group, defaultComponent: component, action: primaryAction),
            showsProgress: model.isBusy && !isActive,
            open: {
                withAnimation(.easeOut(duration: 0.18)) {
                    model.selection = .game(group.id)
                }
            },
            quickAction: {
                if isActive {
                    stopConfirmationGroup = group
                } else {
                    quickAction(for: group)
                }
            }
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.85)
                .delay(Double(animationIndex) * 0.06),
            value: appeared
        )
    }

    /// Multi-component groups get their chooser modals; single games act
    /// directly, exactly as before.
    private func quickAction(for group: GameGroup) {
        guard group.isMultiComponent else {
            model.performPrimaryAction(for: model.defaultComponent(for: group))
            return
        }
        if model.anyComponentInstalled(in: group) {
            launchSheetGroup = group
        } else if model.snapshot.steam.isReady {
            manageSheetGroup = group
        } else {
            model.performPrimaryAction(for: model.defaultComponent(for: group))
        }
    }

    private func groupCardState(_ group: GameGroup) -> ComponentState {
        if model.anyComponentInstalled(in: group) {
            return .ready("Installed")
        }
        return model.snapshot.game(model.defaultComponent(for: group)).state
    }

    private func groupPrimaryAction(
        _ group: GameGroup,
        defaultComponent: GameDescriptor
    ) -> PrimaryAction {
        if group.components.contains(where: { model.primaryAction(for: $0) == .play }) {
            return .play
        }
        return model.primaryAction(for: defaultComponent)
    }

    private func groupInstallStatus(_ group: GameGroup) -> String? {
        guard group.isMultiComponent else { return nil }
        let installedCount = group.components.count {
            model.snapshot.game($0).state.isReady
        }
        guard installedCount > 0, installedCount < group.components.count else { return nil }
        return "\(installedCount) of \(group.components.count) installed"
    }

    private func groupStatus(_ group: GameGroup) -> String? {
        if model.isGroupLaunching(group) { return "Launching" }
        if model.isGroupRunning(group) { return "Running" }
        return groupInstallStatus(group)
    }

    private func groupQuickActionTitle(
        _ group: GameGroup,
        defaultComponent: GameDescriptor,
        action: PrimaryAction
    ) -> String {
        guard group.isMultiComponent else { return action.title(for: defaultComponent) }
        if action == .play {
            return "Choose a mode to play \(group.shortTitle)"
        }
        if action == .installGame, model.snapshot.steam.isReady {
            return "Choose components to install"
        }
        return action.title(for: defaultComponent)
    }
}

private struct GameCard: View {
    let descriptor: GameDescriptor
    let artwork: [URL]
    var displayTitle: String?
    var accessibilityTitle: String?
    let state: ComponentState
    var statusOverride: String?
    var isActive = false
    var isLocked = false
    let primaryAction: PrimaryAction
    var quickActionSymbol: String?
    var quickActionTitle: String?
    let showsProgress: Bool
    let open: () -> Void
    let quickAction: () -> Void

    @State private var isHovering = false

    var body: some View {
        card
            .onTapGesture { if !isLocked { open() } }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(accessibilityTitle ?? descriptor.title), \(statusText)")
            .accessibilityHint(isLocked ? "Unavailable while another game is active" : "")
            .accessibilityHidden(isLocked)
    }

    private var card: some View {
            GameArtwork(candidates: artwork, fallbackSymbol: descriptor.symbol)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.62),
                            .init(color: .black.opacity(0.78), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayTitle ?? descriptor.shortTitle)
                            .font(.system(size: SecundaTheme.FontSize.lead, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                        Text(statusText)
                            .font(.system(size: SecundaTheme.FontSize.small, weight: .medium))
                            .foregroundStyle(statusColor)
                    }
                    .padding(16)
                }
                .overlay {
                    if isHovering {
                        Button(action: quickAction) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 64, height: 64)
                                    .overlay {
                                        Circle().stroke(Color.white.opacity(0.35))
                                    }
                                if showsProgress {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: quickActionSymbol ?? primaryAction.symbol)
                                        .font(.system(size: 23, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(showsProgress)
                        .accessibilityLabel(quickActionTitle ?? primaryAction.title(for: descriptor))
                        .help(quickActionTitle ?? primaryAction.title(for: descriptor))
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: SecundaTheme.Radius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SecundaTheme.Radius.lg, style: .continuous)
                        .stroke(
                            isHovering ? SecundaTheme.frost.opacity(0.6) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: .black.opacity(isHovering ? 0.55 : 0.3),
                    radius: isHovering ? 30 : 16,
                    y: isHovering ? 16 : 9
                )
                .scaleEffect(isHovering && !isLocked ? 1.04 : 1)
                .saturation(isLocked ? 0.08 : 1)
                .opacity(isLocked ? 0.46 : 1)
                .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isHovering)
                .contentShape(RoundedRectangle(cornerRadius: SecundaTheme.Radius.lg, style: .continuous))
                .onHover { isHovering = !isLocked && $0 }
                .allowsHitTesting(!isLocked)
    }

    private var statusText: String {
        if isActive, let statusOverride { return statusOverride }
        if let statusOverride { return statusOverride }
        return switch state {
        case .ready: "Installed"
        case .warning(let detail): detail
        case .failed(let detail): detail
        case .working(let detail): detail
        case .missing: "Not installed"
        }
    }

    private var statusColor: Color {
        if isActive { return SecundaTheme.aurora }
        return switch state {
        case .ready: SecundaTheme.moon.opacity(0.85)
        case .warning, .failed: SecundaTheme.ember
        default: Color.white.opacity(0.75)
        }
    }
}
