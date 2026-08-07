import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: LauncherViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    eyebrow: "PROFILE",
                    title: "A quiet, tested default.",
                    detail: "These options affect only Skyrim inside Secunda’s selected game space."
                )

                VStack(alignment: .leading, spacing: 20) {
                    SectionHeading(title: "Display", detail: "Applied at launch")
                    Toggle("Launch in a window", isOn: setting(\.launchInWindow))
                    Text(model.settings.launchInWindow
                        ? "Windowed mode is useful for setup. Fullscreen is recommended for the smoothest play and macOS Game Mode eligibility."
                        : "Fullscreen is selected so macOS can prioritize the game when Game Mode is available.")
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)

                    HStack {
                        Text("Resolution")
                        Spacer()
                        Picker("Resolution", selection: resolutionBinding) {
                            Text("1920 × 1080").tag("1920x1080")
                            Text("1728 × 1117").tag("1728x1117")
                            Text("1440 × 900").tag("1440x900")
                            Text("1280 × 800").tag("1280x800")
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
                .secundaPanel()

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
                        Text("Keep fullscreen selected when you want macOS to give the game its highest scheduling priority.")
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
                    Toggle("Write detailed Wine logs", isOn: setting(\.enableDiagnostics))
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

    private func setting<T>(_ keyPath: WritableKeyPath<LauncherSettings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: {
                model.settings[keyPath: keyPath] = $0
                model.persistSettings()
            }
        )
    }

    private var resolutionBinding: Binding<String> {
        Binding(
            get: { "\(model.settings.width)x\(model.settings.height)" },
            set: { value in
                let parts = value.split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2 else { return }
                model.settings.width = parts[0]
                model.settings.height = parts[1]
                model.persistSettings()
            }
        )
    }
}
