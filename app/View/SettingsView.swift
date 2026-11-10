import SwiftUI

/// Launcher-level settings, support, and recovery. Per-game display and
/// audio options live on each game's own page in the library.
struct SettingsView: View {
    @ObservedObject var model: LauncherViewModel
    @EnvironmentObject private var updater: AppUpdater
    @State private var copied = false
    @State private var showsForceStopAllConfirmation = false

    private var updateTitle: String {
        switch updater.status {
        case .available(let version): "Secunda \(version) is available"
        case .upToDate: "Secunda is up to date"
        case .unknown: "Updates"
        }
    }

    private var updateDetail: String {
        let schedule = updater.checksAutomatically ? "Checks once a day" : "Automatic checks are off"
        guard let date = updater.lastCheckDate else { return schedule }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let checked = formatter.localizedString(for: date, relativeTo: Date())
        return "Last checked \(checked) · \(schedule)"
    }

    private var updateRow: some View {
        let hasUpdate = updater.status.availableVersion != nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: hasUpdate ? "arrow.down.circle.fill" : "checkmark.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(hasUpdate ? SecundaTheme.frost : SecundaTheme.secondaryText)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(updateTitle)
                        .font(.system(size: SecundaTheme.FontSize.body, weight: .medium))
                        .foregroundStyle(SecundaTheme.text)
                    Text(updateDetail)
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)
                }
                Spacer(minLength: 12)
                if hasUpdate {
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Label("Update", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(SecundaActionButtonStyle(prominent: true))
                    .help("See what's new, then download and install")
                } else {
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(SecundaIconButtonStyle())
                    .help("Check for updates now")
                    .accessibilityLabel("Check for updates")
                    .disabled(!updater.canCheckForUpdates)
                }
            }
            Toggle(isOn: Binding(
                get: { updater.checksAutomatically },
                set: { updater.checksAutomatically = $0 }
            )) {
                Text("Check for updates automatically")
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.secondaryText)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(SecundaTheme.frost)
        }
        .padding(14)
        .frame(maxWidth: 560, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: SecundaTheme.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: SecundaTheme.Radius.md, style: .continuous)
                .strokeBorder(
                    hasUpdate ? SecundaTheme.frost.opacity(0.45) : SecundaTheme.hairline,
                    lineWidth: 1
                )
        }
        .animation(.easeOut(duration: 0.2), value: updater.status)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                PageHeader(
                    eyebrow: "LAUNCHER",
                    title: "Settings",
                    detail: "These options apply to Secunda itself. Display and audio for each game live on that game’s page."
                )

                if updater.isAvailable {
                    FlatSection(title: "Updates", detail: AppVersion.label) {
                        updateRow
                    }
                }

                FlatSection(title: "Performance", detail: "This Mac") {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.snapshot.lowPowerModeEnabled {
                            Label("Low Power Mode is limiting game performance", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(SecundaTheme.ember)
                            Text("For full frame rate, turn off Low Power Mode for the current power source in System Settings › Battery › Energy Mode before playing.")
                                .font(.caption)
                                .foregroundStyle(SecundaTheme.secondaryText)
                        } else {
                            Label("Full performance is available", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(SecundaTheme.aurora)
                            Text("Games get macOS’s highest scheduling priority in fullscreen when Game Mode is available.")
                                .font(.caption)
                                .foregroundStyle(SecundaTheme.secondaryText)
                        }
                        Text("Secunda reports this setting but never changes your Mac’s global power mode for you.")
                            .font(.caption2)
                            .foregroundStyle(SecundaTheme.secondaryText)
                    }
                }

                FlatSection(title: "Secunda Runtime", detail: model.snapshot.runtime.detail ?? "Unavailable") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.snapshot.runtime.isReady
                            ? "This copy uses the bundled runtime, verified before use."
                            : "The compatibility runtime is missing from this copy. Reinstall the complete Secunda package or rebuild it from source.")
                            .font(.caption)
                            .foregroundStyle(SecundaTheme.secondaryText)
                            .frame(maxWidth: 560, alignment: .leading)

                        Button {
                            model.revealApplicationData()
                        } label: {
                            Label("Reveal Secunda Data", systemImage: "folder")
                        }
                        .buttonStyle(SecundaActionButtonStyle())
                    }
                }

                FlatSection(
                    title: "Running Processes",
                    detail: model.bottleProcesses.isEmpty
                        ? "None detected"
                        : "\(model.bottleProcesses.count) running"
                ) {
                    runningProcesses
                }

                FlatSection(title: "Cover Art", detail: "Optional") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Secunda loads cover art from Steam. To use your own, drop an image into the Artwork folder named after the game — \(artworkExampleNames) — as .png or .jpg. Add “-hero” to the name for the wide banner. Your images always win over Steam's.")
                            .font(.caption)
                            .foregroundStyle(SecundaTheme.secondaryText)
                            .lineSpacing(3)
                            .frame(maxWidth: 560, alignment: .leading)

                        Button {
                            model.revealArtworkFolder()
                        } label: {
                            Label("Open Artwork Folder", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(SecundaActionButtonStyle())
                    }
                }

                FlatSection(title: "Compatibility", detail: "Applies to every game") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Fast synchronization", isOn: fastSyncBinding)
                            .toggleStyle(.switch)
                        Text(fastSyncCaption)
                            .font(.caption)
                            .foregroundStyle(SecundaTheme.secondaryText)
                            .lineSpacing(3)
                            .frame(maxWidth: 560, alignment: .leading)
                    }
                }

                FlatSection(title: "Diagnostics", detail: "Off by default") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Write detailed logs", isOn: diagnosticsBinding)
                            .toggleStyle(.switch)
                        Text("Detailed logs can be large. Secunda never records Steam passwords or reads unrelated documents.")
                            .font(.caption)
                            .foregroundStyle(SecundaTheme.secondaryText)
                    }
                }

                FlatSection(title: "Support", detail: "Logs and recovery") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(model.diagnosticReport, forType: .string)
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy Diagnostic Report", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(SecundaActionButtonStyle())

                            Button {
                                model.revealLogs()
                            } label: {
                                Label("Reveal Logs", systemImage: "folder.badge.gearshape")
                            }
                            .buttonStyle(SecundaActionButtonStyle())

                            if !installedDescriptors.isEmpty {
                                Menu {
                                    ForEach(installedDescriptors) { descriptor in
                                        Button(descriptor.title) {
                                            model.verifyGameFiles(descriptor)
                                        }
                                    }
                                } label: {
                                    Label("Verify Game Files…", systemImage: "checkmark.shield")
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                                .buttonStyle(SecundaActionButtonStyle())
                            }
                        }

                        Text(model.diagnosticReport)
                            .font(.system(size: SecundaTheme.FontSize.small, design: .monospaced))
                            .foregroundStyle(SecundaTheme.secondaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.black.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: SecundaTheme.Radius.md, style: .continuous))

                        DisclosureGroup("Latest runtime log") {
                            Text(model.latestLogExcerpt)
                                .font(.system(size: SecundaTheme.FontSize.small, design: .monospaced))
                                .foregroundStyle(SecundaTheme.secondaryText)
                                .textSelection(.enabled)
                                .padding(.top, 12)
                        }
                        .font(.system(size: SecundaTheme.FontSize.body, weight: .medium))
                    }
                }

                FlatSection(title: "About", detail: AppVersion.label) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Unofficial launcher", systemImage: "checkmark.shield")
                            .font(.system(size: SecundaTheme.FontSize.body, weight: .medium))
                        Text("Secunda is an unofficial community project, unaffiliated with Valve, Bethesda, or any game publisher. You need your own Steam copy of each game. Secunda never asks for a Steam password and never ships Steam, game files, or account data.")
                            .font(.caption)
                            .foregroundStyle(SecundaTheme.secondaryText)
                            .lineSpacing(3)
                            .frame(maxWidth: 560, alignment: .leading)
                        HStack(spacing: 18) {
                            Link("Terms of Use", destination: URL(string: "https://github.com/lukekabbash/secunda-launcher/blob/source-only-secunda/TERMS.md")!)
                            Link("Privacy Policy", destination: URL(string: "https://github.com/lukekabbash/secunda-launcher/blob/source-only-secunda/PRIVACY.md")!)
                        }
                        .font(.caption)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(42)
            .frame(maxWidth: 880, alignment: .leading)
            // Column floats centered in the pane; content stays left-aligned.
            .frame(maxWidth: .infinity)
        }
    }

    private var runningProcesses: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    model.refreshBottleProcesses()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecundaActionButtonStyle())

                Spacer()

                if !model.bottleProcesses.isEmpty {
                    Button {
                        showsForceStopAllConfirmation = true
                    } label: {
                        Label("Force Stop All", systemImage: "stop.fill")
                    }
                    .buttonStyle(SecundaDestructiveButtonStyle())
                }
            }

            if model.bottleProcesses.isEmpty {
                Text("No Secunda-managed processes are currently running.")
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.bottleProcesses) { process in
                        HStack(spacing: 12) {
                            Text(String(process.pid))
                                .font(.system(size: SecundaTheme.FontSize.small, design: .monospaced))
                                .foregroundStyle(SecundaTheme.secondaryText)
                                .frame(width: 52, alignment: .trailing)
                            Text(process.displayName)
                                .font(.system(size: SecundaTheme.FontSize.body, weight: .medium))
                                .lineLimit(1)
                            if process.isOrphaned {
                                Text("STUCK")
                                    .font(.system(size: SecundaTheme.FontSize.micro, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(SecundaTheme.ember)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background {
                                        Capsule().fill(SecundaTheme.ember.opacity(0.14))
                                    }
                            }
                            Spacer()
                            Button("Force Stop") {
                                model.forceStopProcesses([process])
                            }
                            .buttonStyle(SecundaDestructiveButtonStyle())
                        }
                        .padding(.vertical, 4)
                    }
                }
                Text("Force-stopping skips the game’s save-and-quit path. Stuck entries lost their session and can only be removed this way.")
                    .font(.caption2)
                    .foregroundStyle(SecundaTheme.secondaryText)
            }
        }
        .onAppear { model.refreshBottleProcesses() }
        .confirmationDialog(
            "Force stop everything in the game space?",
            isPresented: $showsForceStopAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Force Stop All", role: .destructive) {
                model.forceStopEverything()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This immediately stops every process in Secunda’s game space — games, Steam, and background compatibility work. Unsaved progress is lost.")
        }
    }

    private var artworkExampleNames: String {
        GameDescriptor.supported.prefix(2).map { "\($0.id).jpg" }.joined(separator: ", ")
    }

    private var installedDescriptors: [GameDescriptor] {
        GameDescriptor.supported.filter { model.snapshot.game($0).state.isReady }
    }

    private var fastSyncBinding: Binding<Bool> {
        Binding(
            get: { model.settings.useFastSync },
            set: {
                model.settings.useFastSync = $0
                model.persistSettings()
            }
        )
    }

    private var fastSyncCaption: String {
        if model.hasPendingFastSyncChange {
            let requested = model.settings.useFastSync ? "on" : "off"
            let active = model.settings.activeFastSync ? "on" : "off"
            return "Queued: \(requested). This game space stays \(active) until Steam and every game are closed. Secunda applies the change before the next process starts."
        }
        return model.settings.activeFastSync
            ? "Fast synchronization is on. If a game closes immediately on start, turn this off and close the game space."
            : "Fast synchronization is off."
    }

    private var diagnosticsBinding: Binding<Bool> {
        Binding(
            get: { model.settings.enableDiagnostics },
            set: {
                model.settings.enableDiagnostics = $0
                model.persistSettings()
            }
        )
    }
}
