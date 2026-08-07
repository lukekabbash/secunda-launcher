import SwiftUI

/// Launcher-level settings. Per-game display and audio options live on each
/// game's own page in the library.
struct SettingsView: View {
    @ObservedObject var model: LauncherViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    eyebrow: "LAUNCHER",
                    title: "A quiet, tested default.",
                    detail: "These options affect Secunda itself. Game-specific display and audio settings live on each game’s page."
                )

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Performance", detail: "Live Mac check")
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
                .secundaPanel()

                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "Secunda Engine", detail: model.snapshot.runtime.detail ?? "Unavailable")
                    Text(model.snapshot.runtime.isReady
                        ? "Bundled with this copy of Secunda and verified before use."
                        : "Secunda engine unavailable")
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)

                    Text("Secunda uses only its own source-built compatibility engine. There is no player-facing runtime picker.")
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)

                    if !model.snapshot.runtime.isReady {
                        Text("The engine is missing from this copy. Reinstall the complete Secunda package or rebuild the runtime from source.")
                            .font(.caption)
                            .foregroundStyle(SecundaTheme.secondaryText)
                    }

                    Button("Reveal Secunda Data") { model.revealApplicationData() }
                        .buttonStyle(.plain)
                        .foregroundStyle(SecundaTheme.frost)
                }
                .secundaPanel()

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Diagnostics", detail: "Off by default")
                    Toggle("Write detailed Wine logs", isOn: diagnosticsBinding)
                    Text("Detailed logs can be large. Secunda never records Steam passwords or reads unrelated documents.")
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)
                }
                .secundaPanel()
            }
            .padding(42)
            .frame(maxWidth: 860, alignment: .leading)
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
