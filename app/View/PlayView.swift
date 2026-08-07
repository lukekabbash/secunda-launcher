import SwiftUI

struct PlayView: View {
    @ObservedObject var model: LauncherViewModel
    @State private var showsCloseConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero

                HStack(alignment: .top, spacing: 18) {
                    readiness
                    recentActivity
                }
            }
            .padding(42)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SKYRIM SPECIAL EDITION")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.4)
                .foregroundStyle(SecundaTheme.frost)

            Text(model.headline)
                .font(.system(size: 40, weight: .medium, design: .serif))
                .tracking(-0.6)

            Text(model.supportingText)
                .font(.system(size: 15))
                .foregroundStyle(SecundaTheme.secondaryText)
                .lineSpacing(4)
                .frame(maxWidth: 590, alignment: .leading)

            HStack(spacing: 14) {
                Button {
                    model.performPrimaryAction()
                } label: {
                    HStack(spacing: 10) {
                        if model.isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: model.primaryAction.symbol)
                        }
                        Text(model.primaryAction.title)
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
            }
            .padding(.top, 4)

            if let progress = model.setupProgress {
                setupProgressRail(progress)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                setupJourneyRail(model.setupJourney)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .animation(.easeInOut(duration: 0.24), value: model.setupProgress)
        .confirmationDialog(
            "Close this Secunda game space?",
            isPresented: $showsCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close Skyrim and Steam", role: .destructive) {
                model.stop()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Save your game first. This closes every Windows app in this Secunda game space.")
        }
    }

    private func setupJourneyRail(_ journey: SetupJourney) -> some View {
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

    private func setupProgressRail(_ progress: SetupProgress) -> some View {
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

    private var readiness: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "Secunda setup", detail: "One separate installation")
            StatusRow(title: "This Mac", symbol: "desktopcomputer", state: model.snapshot.host)
            StatusRow(title: "Secunda Engine", symbol: "shippingbox.fill", state: model.snapshot.runtime)
            StatusRow(title: "Separate Windows Space", symbol: "cube.transparent", state: model.snapshot.bottle)
            StatusRow(title: "Steam Client", symbol: "person.crop.circle", state: model.snapshot.steam)
            StatusRow(title: "Skyrim", symbol: "mountain.2.fill", state: model.snapshot.game)
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
}

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
