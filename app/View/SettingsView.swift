import SwiftUI

/// Launcher-level settings, support, and recovery. Per-game display and
/// audio options live on each game's own page in the library.
struct SettingsView: View {
    @ObservedObject var model: LauncherViewModel
    @State private var copied = false
    @State private var showsForceStopAllConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                PageHeader(
                    eyebrow: "LAUNCHER",
                    title: "A quiet, tested default.",
                    detail: "These options affect Secunda itself. Game-specific display and audio settings live on each game’s page."
                )

                FlatSection(title: "Performance", detail: "Live Mac check") {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.snapshot.lowPowerModeEnabled {
                            Label("Low Power Mode is limiting game performance", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(SecundaTheme.ember)
                            Text("For full frame rate, turn off Low Power Mode for the current power source in System Settings › Battery › Energy Mode before playing.")
                                .font(.caption)
                                .foregroundStyle(SecundaTheme.secondaryText)
                        } else {
                            Label("Full-power mode is available", systemImage: "checkmark.circle.fill")
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

                FlatSection(title: "Secunda Engine", detail: model.snapshot.runtime.detail ?? "Unavailable") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.snapshot.runtime.isReady
                            ? "Bundled with this copy of Secunda, verified before use, and built only from open source. There is no player-facing runtime picker."
                            : "The engine is missing from this copy. Reinstall the complete Secunda package or rebuild the runtime from source.")
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

                FlatSection(title: "Diagnostics", detail: "Off by default") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Write detailed Wine logs", isOn: diagnosticsBinding)
                            .toggleStyle(.switch)
                        Text("Detailed logs can be large. Secunda never records Steam passwords or reads unrelated documents.")
                            .font(.caption)
                            .foregroundStyle(SecundaTheme.secondaryText)
                    }
                }

                FlatSection(title: "Support", detail: "No mystery failures") {
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

                            ForEach(GameDescriptor.supported) { descriptor in
                                if model.snapshot.game(descriptor).state.isReady {
                                    Button("Verify \(descriptor.shortTitle) Files") {
                                        model.verifyGameFiles(descriptor)
                                    }
                                    .buttonStyle(SecundaActionButtonStyle())
                                }
                            }
                        }

                        Text(model.diagnosticReport)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SecundaTheme.secondaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.black.opacity(0.25))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        DisclosureGroup("Latest runtime log") {
                            Text(model.latestLogExcerpt)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(SecundaTheme.secondaryText)
                                .textSelection(.enabled)
                                .padding(.top, 12)
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                }

                FlatSection(title: "About", detail: "v0.1") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Unofficial launcher", systemImage: "checkmark.shield")
                            .font(.system(size: 13, weight: .medium))
                        Text("Secunda is an unofficial community project, unaffiliated with Valve, Bethesda, or any game publisher. Each game requires your own separately purchased Steam copy. Secunda never bundles Steam, game files, or account data, and never asks for your Steam password.")
                            .font(.caption)
                            .foregroundStyle(SecundaTheme.secondaryText)
                            .lineSpacing(3)
                            .frame(maxWidth: 560, alignment: .leading)
                    }
                }
            }
            .padding(42)
            .frame(maxWidth: 880, alignment: .leading)
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
                            .foregroundStyle(SecundaTheme.ember)
                    }
                    .buttonStyle(SecundaActionButtonStyle())
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
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(SecundaTheme.secondaryText)
                                .frame(width: 52, alignment: .trailing)
                            Text(process.displayName)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                            if process.isOrphaned {
                                Text("ORPHANED")
                                    .font(.system(size: 8.5, weight: .bold))
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
                            .buttonStyle(SecundaActionButtonStyle())
                        }
                        .padding(.vertical, 4)
                    }
                }
                Text("Force-stopping skips the game's own save-and-quit path. Orphaned entries lost their Wine session and can only be removed this way.")
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
            Text("Immediately kills every Windows process in Secunda's game space — games, Steam, and Wine workers. Unsaved progress is lost.")
        }
    }

    private var artworkExampleNames: String {
        GameDescriptor.supported.prefix(2).map { "\($0.id).jpg" }.joined(separator: ", ")
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
