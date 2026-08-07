import SwiftUI

struct GamesGridView: View {
    @ObservedObject var model: LauncherViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 24)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                PageHeader(
                    eyebrow: "LIBRARY",
                    title: "Your games.",
                    detail: "Windows games from your own Steam library, played through Secunda’s free source-built engine. Select a game to set it up, tune it, and play."
                )

                LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                    ForEach(GameDescriptor.supported) { descriptor in
                        GameCard(
                            descriptor: descriptor,
                            state: model.snapshot.game(descriptor).state
                        ) {
                            withAnimation(.easeOut(duration: 0.18)) {
                                model.selection = .game(descriptor.id)
                            }
                        }
                    }
                }

                Text("Game artwork is loaded from Steam. Each game requires your own Steam purchase; Secunda never bundles game files.")
                    .font(.caption2)
                    .foregroundStyle(SecundaTheme.secondaryText)
            }
            .padding(42)
            .frame(maxWidth: 1080, alignment: .leading)
        }
    }
}

private struct GameCard: View {
    let descriptor: GameDescriptor
    let state: ComponentState
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                artwork
                footer
            }
            .background(Color.white.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isHovering ? SecundaTheme.frost.opacity(0.55) : SecundaTheme.hairline)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(
                color: .black.opacity(isHovering ? 0.5 : 0.28),
                radius: isHovering ? 26 : 14,
                y: isHovering ? 14 : 8
            )
            .scaleEffect(isHovering ? 1.035 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.75), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel("\(descriptor.title), \(state.isReady ? "installed" : "not installed")")
    }

    private var artwork: some View {
        GameArtwork(url: descriptor.cardArtworkURL, fallbackSymbol: descriptor.symbol)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                LinearGradient(
                    colors: [
                        .clear,
                        .clear,
                        .black.opacity(isHovering ? 0.15 : 0.4)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                if isHovering {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 58, height: 58)
                        Image(systemName: state.isReady ? "play.fill" : "arrow.down.circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isHovering)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: descriptor.symbol)
                .font(.system(size: 13))
                .foregroundStyle(SecundaTheme.frost)
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.shortTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SecundaTheme.text)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SecundaTheme.secondaryText.opacity(isHovering ? 1 : 0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.6))
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
        default: SecundaTheme.secondaryText
        }
    }
}
