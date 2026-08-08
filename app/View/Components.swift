import SwiftUI

/// Composed, reusable views. Tokens and control styles live in Theme.swift.

/// Flat content section: an uppercase heading over a hairline, no box.
/// The restrained alternative to nesting panels.
struct FlatSection<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title.uppercased())
                        .font(.system(size: SecundaTheme.FontSize.small, weight: .semibold))
                        .tracking(2.0)
                        .foregroundStyle(SecundaTheme.frost)
                    Spacer()
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(SecundaTheme.secondaryText)
                    }
                }
                Rectangle()
                    .fill(SecundaTheme.hairline)
                    .frame(height: 1)
            }
            content
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
                .font(.system(size: SecundaTheme.FontSize.small, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(SecundaTheme.frost)
            Text(title)
                .font(.system(size: SecundaTheme.FontSize.hero, weight: .medium, design: .serif))
            Text(detail)
                .font(.system(size: SecundaTheme.FontSize.lead))
                .foregroundStyle(SecundaTheme.secondaryText)
                .lineSpacing(4)
                .frame(maxWidth: 620, alignment: .leading)
        }
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
                    .font(.system(size: SecundaTheme.FontSize.body, weight: .medium))
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
        case .failed: SecundaTheme.danger
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

struct SetupJourneyRail: View {
    let journey: SetupJourney

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(journey.title)
                    .font(.system(size: SecundaTheme.FontSize.body, weight: .semibold))
                Spacer()
                Text(journey.label)
                    .font(.system(size: SecundaTheme.FontSize.small, weight: .medium, design: .monospaced))
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
            RoundedRectangle(cornerRadius: SecundaTheme.Radius.md, style: .continuous)
                .stroke(SecundaTheme.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: SecundaTheme.Radius.md, style: .continuous))
        .frame(maxWidth: 590)
    }
}

struct SetupProgressRail: View {
    let progress: SetupProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(progress.title)
                    .font(.system(size: SecundaTheme.FontSize.body, weight: .semibold))
                Spacer()
                Text(progress.stepLabel)
                    .font(.system(size: SecundaTheme.FontSize.small, weight: .medium, design: .monospaced))
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
            RoundedRectangle(cornerRadius: SecundaTheme.Radius.md, style: .continuous)
                .stroke(SecundaTheme.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: SecundaTheme.Radius.md, style: .continuous))
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
