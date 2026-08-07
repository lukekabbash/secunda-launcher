import SwiftUI

struct GamesGridView: View {
    @ObservedObject var model: LauncherViewModel
    @State private var appeared = false

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
                    ForEach(Array(GameDescriptor.supported.enumerated()), id: \.element.id) { index, descriptor in
                        GameCard(
                            descriptor: descriptor,
                            state: model.snapshot.game(descriptor).state
                        ) {
                            withAnimation(.easeOut(duration: 0.18)) {
                                model.selection = .game(descriptor.id)
                            }
                        }
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
    }
}

private struct GameCard: View {
    let descriptor: GameDescriptor
    let state: ComponentState
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
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
                        Text(descriptor.shortTitle)
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
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 60, height: 60)
                            Image(systemName: state.isReady ? "play.fill" : "arrow.down.circle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                        }
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
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(descriptor.title), \(state.isReady ? "installed" : "not installed")")
    }

    private var statusText: String {
        switch state {
        case .ready: "Installed"
        case .warning(let detail): detail
        case .failed(let detail): detail
        case .working(let detail): detail
        case .missing: "Not installed"
        }
    }

    private var statusColor: Color {
        switch state {
        case .ready: SecundaTheme.aurora
        case .warning, .failed: SecundaTheme.ember
        default: Color.white.opacity(0.75)
        }
    }
}
