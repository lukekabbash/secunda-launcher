import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: LauncherViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    eyebrow: "PROFILE",
                    title: "A quiet, tested default.",
                    detail: "These options affect only Skyrim inside Secunda’s managed bottle."
                )

                VStack(alignment: .leading, spacing: 20) {
                    SectionHeading(title: "Display", detail: "Applied at launch")
                    Toggle("Launch in a window", isOn: setting(\.launchInWindow))

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

                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "Secunda Engine", detail: model.snapshot.runtime.detail ?? "Unavailable")
                    Text(model.snapshot.runtimePath ?? "Secunda engine unavailable")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(SecundaTheme.secondaryText)
                        .textSelection(.enabled)

                    Text("Secunda automatically uses the compatible engine it finds. There is no player-facing runtime picker.")
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)

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
