import SwiftUI

struct GamesGridView: View {
    @ObservedObject var model: LauncherViewModel
    @State private var appeared = false
    @State private var launchSheetGroup: GameGroup?
    @State private var manageSheetGroup: GameGroup?

    private let columns = [
        GridItem(.adaptive(minimum: 216, maximum: 280), spacing: 28)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                PageHeader(
                    eyebrow: "LIBRARY",
                    title: "Your games.",
                    detail: "Windows games from your own Steam library, played through Secunda’s free source-built engine."
                )

                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(Array(GameGroup.all.enumerated()), id: \.element.id) { index, group in
                        let component = model.defaultComponent(for: group)
                        GameCard(
                            descriptor: component,
                            displayTitle: group.shortTitle,
                            state: groupCardState(group),
                            isRunning: model.runningComponent(in: group) != nil,
                            primaryAction: model.primaryAction(for: component),
                            isBusy: model.isBusy,
                            open: {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    model.selection = .game(group.id)
                                }
                            },
                            quickAction: {
                                quickAction(for: group)
                            }
                        )
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 18)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.85)
                                .delay(Double(index) * 0.06),
                            value: appeared
                        )
                    }
                }
            }
            .padding(42)
            .frame(maxWidth: 1120, alignment: .leading)
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
}

private struct GameCard: View {
    let descriptor: GameDescriptor
    var displayTitle: String?
    let state: ComponentState
    var isRunning = false
    let primaryAction: PrimaryAction
    let isBusy: Bool
    let open: () -> Void
    let quickAction: () -> Void

    @State private var isHovering = false

    var body: some View {
        card
            .onTapGesture(perform: open)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(descriptor.title), \(state.isReady ? "installed" : "not installed")")
    }

    private var card: some View {
            GameArtwork(url: descriptor.cardArtworkURL, fallbackSymbol: descriptor.symbol)
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
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                        Text(statusText)
                            .font(.system(size: 10.5, weight: .medium))
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
                                if isBusy {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: primaryAction.symbol)
                                        .font(.system(size: 23, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy)
                        .help(primaryAction.title(for: descriptor))
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                .scaleEffect(isHovering ? 1.04 : 1)
                .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isHovering)
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onHover { isHovering = $0 }
    }

    private var statusText: String {
        if isRunning { return "Running" }
        return switch state {
        case .ready: "Installed"
        case .warning(let detail): detail
        case .failed(let detail): detail
        case .working(let detail): detail
        case .missing: "Not installed"
        }
    }

    private var statusColor: Color {
        if isRunning { return SecundaTheme.aurora }
        return switch state {
        case .ready: SecundaTheme.moon.opacity(0.85)
        case .warning, .failed: SecundaTheme.ember
        default: Color.white.opacity(0.75)
        }
    }
}
