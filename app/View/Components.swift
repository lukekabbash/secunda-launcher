import SwiftUI

struct SectionHeading: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)
        }
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(SecundaTheme.frost)
            Text(title)
                .font(.system(size: 34, weight: .medium, design: .serif))
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(SecundaTheme.secondaryText)
                .lineSpacing(4)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }
}

struct MetricPanel: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(SecundaTheme.frost)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .medium, design: .serif))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.secondaryText)
            }
            Spacer()
        }
        .secundaPanel()
        .frame(maxWidth: .infinity)
    }
}

struct StatusRow: View {
    let title: String
    let symbol: String
    let state: ComponentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(SecundaTheme.frost)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let detail = state.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .accessibilityLabel(statusLabel)
        }
        .padding(.vertical, 3)
    }

    private var statusSymbol: String {
        switch state {
        case .ready: "checkmark.circle.fill"
        case .working: "arrow.triangle.2.circlepath.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        case .missing: "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch state {
        case .ready: SecundaTheme.aurora
        case .working: SecundaTheme.frost
        case .warning: SecundaTheme.ember
        case .failed: .red.opacity(0.8)
        case .missing: SecundaTheme.secondaryText
        }
    }

    private var statusLabel: String {
        switch state {
        case .ready: "Ready"
        case .working: "Working"
        case .warning: "Needs attention"
        case .failed: "Failed"
        case .missing: "Not ready"
        }
    }
}

struct SecundaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(SecundaTheme.void)
            .background(
                LinearGradient(
                    colors: [SecundaTheme.moon, SecundaTheme.frost],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: SecundaTheme.frost.opacity(configuration.isPressed ? 0.12 : 0.25), radius: 14, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SecundaSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(SecundaTheme.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.11 : 0.065))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(SecundaTheme.hairline)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct SetupJourneyRail: View {
    let journey: SetupJourney

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(journey.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(journey.label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(SecundaTheme.frost)
            }

            ProgressView(value: journey.fraction)
                .tint(SecundaTheme.aurora)

            Text(journey.detail)
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)
        }
        .padding(16)
        .background(Color.white.opacity(0.035))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SecundaTheme.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: 590)
    }
}

struct SetupProgressRail: View {
    let progress: SetupProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(progress.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(progress.stepLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(SecundaTheme.frost)
            }

            ProgressView(value: progress.fraction)
                .tint(SecundaTheme.frost)

            Text(progress.detail)
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)
        }
        .padding(16)
        .background(Color.white.opacity(0.045))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SecundaTheme.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: 590)
    }
}

/// Steam CDN artwork with a stylized gradient fallback so the library looks
/// intentional even offline.
struct GameArtwork: View {
    /// Tried in order; a player-supplied file URL belongs first.
    let candidates: [URL]
    let fallbackSymbol: String
    /// Wide art in a portrait frame is letterboxed over a blurred copy of
    /// itself rather than cropped to nothing.
    var cropsToFill = false

    @ObservedObject private var store = ArtworkStore.shared

    private var key: String {
        candidates.first?.absoluteString ?? fallbackSymbol
    }

    var body: some View {
        Color.clear
            .overlay {
                if let image = store.image(forKey: key) {
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 26)
                            .opacity(0.6)
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: cropsToFill ? .fill : .fit)
                    }
                    .transition(.opacity)
                } else {
                    fallback
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.25), value: store.revision)
            .onAppear { store.load(key: key, candidates: candidates) }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SecundaTheme.void.opacity(0.9),
                    SecundaTheme.frost.opacity(0.25),
                    SecundaTheme.void
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: fallbackSymbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(SecundaTheme.frost.opacity(0.7))
        }
    }
}
