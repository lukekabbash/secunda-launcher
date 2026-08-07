import SwiftUI

/// Launcher-level settings, support, and recovery. Per-game display and
/// audio options live on each game's own page in the library.
struct SettingsView: View {
    @ObservedObject var model: LauncherViewModel
    @State private var copied = false

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
