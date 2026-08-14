import SwiftUI

/// Composed, reusable views. Tokens and control styles live in Theme.swift.

/// Keeps runtime language accurate while older state and activity messages
/// migrate to the current terminology.
func secundaRuntimeTerminology(_ text: String) -> String {
    [
        ("source-built game engine", "source-built Windows compatibility runtime"),
        ("source-built engine", "source-built Windows compatibility runtime"),
        ("Secunda’s free game engine", "Secunda’s free source-built Windows compatibility runtime"),
        ("Secunda Engine", "Secunda Runtime")
    ].reduce(text) { result, replacement in
        result.replacingOccurrences(of: replacement.0, with: replacement.1)
    }
}

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

/// Themed replacement for `.pickerStyle(.segmented)`: a hairline capsule
/// track with a sliding sea-glass pill under the selected segment. Matches
/// the capsule buttons it sits beside in action rows.
struct SecundaSegmentedPicker: View {
    @Binding var selection: String
    let options: [(id: String, title: String)]

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.id) { option in
                Segment(
                    title: option.title,
                    isSelected: option.id == selection,
                    pill: pill
                ) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        selection = option.id
                    }
                }
            }
        }
        .padding(4)
        .background { Capsule().fill(Color.white.opacity(0.04)) }
        .overlay { Capsule().stroke(SecundaTheme.hairline) }
        .frame(height: SecundaTheme.controlHeight)
    }

    private struct Segment: View {
        let title: String
        let isSelected: Bool
        let pill: Namespace.ID
        let select: () -> Void

        @State private var isHovering = false

        var body: some View {
            Button(action: select) {
                Text(title)
                    .font(.system(size: SecundaTheme.FontSize.body, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? SecundaTheme.text : SecundaTheme.secondaryText)
                    .padding(.horizontal, 18)
                    .frame(maxHeight: .infinity)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(SecundaTheme.frost.opacity(0.22))
                                .overlay { Capsule().stroke(SecundaTheme.frost.opacity(0.45)) }
                                .matchedGeometryEffect(id: "selection", in: pill)
                        } else if isHovering {
                            Capsule().fill(Color.white.opacity(0.05))
                        }
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = $0 }
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

extension ComponentState {
    var statusSymbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .working: "arrow.triangle.2.circlepath.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        case .missing: "circle.dashed"
        }
    }

    var statusColor: Color {
        switch self {
        case .ready: SecundaTheme.aurora
        case .working: SecundaTheme.frost
        case .warning: SecundaTheme.ember
        case .failed: SecundaTheme.danger
        case .missing: SecundaTheme.secondaryText
        }
    }

    var statusLabel: String {
        switch self {
        case .ready: "Ready"
        case .working: "Working"
        case .warning: "Needs attention"
        case .failed: "Failed"
        case .missing: "Not ready"
        }
    }

    var needsReadableDetail: Bool {
        switch self {
        case .warning, .failed: true
        default: false
        }
    }
}

/// Colored status indicator; the working state spins slowly so activity is
/// visible without a spinner control.
struct StatusGlyph: View {
    let state: ComponentState

    @State private var spinning = false

    var body: some View {
        Image(systemName: state.statusSymbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(state.statusColor)
            .rotationEffect(.degrees(isWorking && spinning ? 360 : 0))
            .animation(
                isWorking
                    ? .linear(duration: 1.6).repeatForever(autoreverses: false)
                    : .default,
                value: spinning
            )
            .onAppear { spinning = true }
            .accessibilityLabel(state.statusLabel)
    }

    private var isWorking: Bool {
        if case .working = state { return true }
        return false
    }
}

/// The five setup checks as equal cells in one hairline container — a
/// single compact band instead of a five-row list.
struct StatusStrip: View {
    struct Item {
        let title: String
        let state: ComponentState
    }

    let items: [Item]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(SecundaTheme.hairline)
                        .frame(width: 1)
                        .padding(.vertical, 12)
                }
                cell(item)
            }
        }
        .background(Color.white.opacity(0.03))
        .overlay {
            RoundedRectangle(cornerRadius: SecundaTheme.Radius.md, style: .continuous)
                .stroke(SecundaTheme.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: SecundaTheme.Radius.md, style: .continuous))
    }

    private func cell(_ item: Item) -> some View {
        let detail = secundaRuntimeTerminology(item.state.detail ?? item.state.statusLabel)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                StatusGlyph(state: item.state)
                Text(item.title)
                    .font(.system(size: SecundaTheme.FontSize.small, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(detail)
                .font(.caption2)
                .foregroundStyle(SecundaTheme.secondaryText)
                .lineLimit(item.state.needsReadableDetail ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .help(detail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Capsule progress bar: sprung fill, sea-glass gradient, soft glow, and a
/// slow shimmer sweep while work is active.
struct SecundaProgressBar: View {
    let fraction: Double
    var tint: Color = SecundaTheme.frost
    /// Shimmer implies work in flight; a passive checklist stays still.
    var isActive = true

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.8), SecundaTheme.moon],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth(in: geometry.size.width))
                    .overlay {
                        if isActive {
                            shimmer.clipShape(Capsule())
                        }
                    }
                    .shadow(color: tint.opacity(0.45), radius: 7)
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: fraction)
    }

    private func fillWidth(in total: CGFloat) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return max(10, total * min(fraction, 1))
    }

    private var shimmer: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let period = 2.4
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period
            GeometryReader { geometry in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.35), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 70)
                .offset(x: -70 + (geometry.size.width + 140) * phase)
            }
        }
    }
}

/// Progress rail under the action row — one component for both the live
/// setup steps and the passive first-launch journey, so they can't drift.
struct SetupRail: View {
    let title: String
    let label: String
    let detail: String
    let fraction: Double
    var tint: Color = SecundaTheme.frost
    var isActive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(secundaRuntimeTerminology(title))
                    .font(.system(size: SecundaTheme.FontSize.body, weight: .semibold))
                Spacer()
                Text(label)
                    .font(.system(size: SecundaTheme.FontSize.small, weight: .medium, design: .monospaced))
                    .foregroundStyle(SecundaTheme.frost)
            }

            SecundaProgressBar(fraction: fraction, tint: tint, isActive: isActive)

            Text(secundaRuntimeTerminology(detail))
                .font(.caption)
                .foregroundStyle(SecundaTheme.secondaryText)
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
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
            // Multi-mode entries reuse this view while their selected game
            // changes. Key the load to the artwork identity so the new
            // banner is fetched without rebuilding the whole detail page.
            .task(id: key) {
                store.load(key: key, candidates: candidates)
            }
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
