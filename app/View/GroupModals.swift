import SwiftUI

/// Launch chooser for a multi-component group: pick which mode to play.
struct LaunchModeSheet: View {
    @ObservedObject var model: LauncherViewModel
    let group: GameGroup
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PLAY \(group.shortTitle.uppercased())")
                    .font(.system(size: SecundaTheme.FontSize.small, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(SecundaTheme.frost)
                Text("Choose a mode")
                    .font(.system(size: SecundaTheme.FontSize.title, weight: .medium, design: .serif))
            }

            VStack(spacing: 8) {
                ForEach(group.components) { component in
                    ComponentRow(
                        component: component,
                        isInstalled: model.snapshot.game(component).state.isReady,
                        isRunning: model.isGameRunning(component),
                        actionTitle: "Play",
                        actionStyle: .primary,
                        isBusy: model.isBusy
                            || (model.anyGameRunning && !model.isGameRunning(component))
                    ) {
                        model.setDefaultComponent(component, for: group)
                        model.play(component)
                        onDismiss()
                    }
                }
            }

            Text("Modes install separately through Steam. Missing modes can be added in Edit Installation.")
                .font(.caption2)
                .foregroundStyle(SecundaTheme.secondaryText)

            HStack {
                Spacer()
                Button("Cancel", action: onDismiss)
                    .buttonStyle(SecundaActionButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(26)
        .frame(width: 440)
        .background(SecundaTheme.midnight)
    }
}

/// Install manager for a multi-component group: install or remove each
/// component through Steam's own confirmations.
struct ManageInstallSheet: View {
    @ObservedObject var model: LauncherViewModel
    let group: GameGroup
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.shortTitle.uppercased())
                    .font(.system(size: SecundaTheme.FontSize.small, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(SecundaTheme.frost)
                Text("Edit installation")
                    .font(.system(size: SecundaTheme.FontSize.title, weight: .medium, design: .serif))
            }

            VStack(spacing: 8) {
                ForEach(group.components) { component in
                    ComponentRow(
                        component: component,
                        isInstalled: model.snapshot.game(component).state.isReady,
                        isRunning: model.isGameRunning(component),
                        actionTitle: model.snapshot.game(component).state.isReady
                            ? "Uninstall"
                            : "Install",
                        actionStyle: model.snapshot.game(component).state.isReady
                            ? .destructive
                            : .normal,
                        isBusy: model.isBusy
                    ) {
                        if model.snapshot.game(component).state.isReady {
                            model.requestGameUninstall(component)
                        } else {
                            model.requestGameInstall(component)
                        }
                    }
                }
            }

            Text("Steam shows its own confirmation and download progress for each change. Saves and settings stay in place.")
                .font(.caption2)
                .foregroundStyle(SecundaTheme.secondaryText)

            HStack {
                Spacer()
                Button("Done", action: onDismiss)
                    .buttonStyle(SecundaActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 440)
        .background(SecundaTheme.midnight)
    }
}

/// One component row shared by both sheets: artwork, name, status, action.
private struct ComponentRow: View {
    enum ActionStyle {
        case primary
        case normal
        case destructive
    }

    let component: GameDescriptor
    let isInstalled: Bool
    let isRunning: Bool
    let actionTitle: String
    let actionStyle: ActionStyle
    let isBusy: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            GameArtwork(candidates: component.cardArtworkCandidates, fallbackSymbol: component.symbol)
                .frame(width: 34, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: SecundaTheme.Radius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SecundaTheme.Radius.sm, style: .continuous)
                        .stroke(SecundaTheme.hairline)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(component.modeTitle)
                    .font(.system(size: SecundaTheme.FontSize.body, weight: .semibold))
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }
            Spacer()

            if isRunning {
                Text("Running")
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.aurora)
            } else if actionEnabled {
                actionButton
            } else {
                Text("Not installed")
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: SecundaTheme.Radius.md, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.06 : 0.03))
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    /// Play requires the component installed; install/uninstall always applies.
    private var actionEnabled: Bool {
        actionStyle == .primary ? isInstalled : true
    }

    @ViewBuilder
    private var actionButton: some View {
        switch actionStyle {
        case .primary:
            Button(actionTitle, action: action)
                .buttonStyle(SecundaActionButtonStyle(prominent: true))
                .disabled(isBusy)
        case .normal:
            Button(actionTitle, action: action)
                .buttonStyle(SecundaActionButtonStyle())
                .disabled(isBusy)
        case .destructive:
            Button(actionTitle, action: action)
                .buttonStyle(SecundaDestructiveButtonStyle())
                .disabled(isBusy)
        }
    }

    private var statusText: String {
        isInstalled ? "Installed" : "Install through Steam"
    }

    private var statusColor: Color {
        isInstalled ? SecundaTheme.aurora : SecundaTheme.secondaryText
    }
}
