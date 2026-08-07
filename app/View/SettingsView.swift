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
                    HStack {
                        Text("Mode")
                        Spacer()
                        Picker("Mode", selection: setting(\.displayMode)) {
                            Text("Borderless Fullscreen").tag(DisplayMode.borderlessFullscreen)
                            Text("Exclusive Fullscreen").tag(DisplayMode.exclusiveFullscreen)
                            Text("Windowed").tag(DisplayMode.windowed)
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    Text(displayModeCaption)
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)

                    HStack {
                        Text("Resolution")
                        Spacer()
                        Picker("Resolution", selection: resolutionBinding) {
                            ForEach(resolutionOptions) { option in
                                Text(option.label).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 230)
                    }
                    Text("Higher resolutions look sharper but cost frame rate. Your display's own sizes are listed first.")
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)

                    HStack {
                        Text("Field of view")
                        Spacer()
                        Stepper(
                            "\(model.settings.fieldOfView)°",
                            value: setting(\.fieldOfView),
                            in: 70...110,
                            step: 5
                        )
                        .fixedSize()
                    }
                    Text("Skyrim's default is 80°. Applied at launch; takes effect on the next game start.")
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)

                    Toggle("Vertical sync", isOn: setting(\.verticalSync))
                    Text(model.settings.verticalSync
                        ? "VSync caps the frame rate to your display for smooth, tear-free play."
                        : "Uncapped frame rate can cause screen tearing and physics glitches in Skyrim's engine.")
                        .font(.caption)
                        .foregroundStyle(SecundaTheme.secondaryText)
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

    private struct ResolutionOption: Identifiable {
        let width: Int
        let height: Int
        let note: String?

        var id: String { "\(width)x\(height)" }
        var label: String {
            let base = "\(width) × \(height)"
            return note.map { "\(base)  (\($0))" } ?? base
        }
    }

    /// The main display's sizes first, then common Mac panel resolutions,
    /// then whatever custom value is already saved so the picker never
    /// shows an empty selection.
    private var resolutionOptions: [ResolutionOption] {
        var options: [ResolutionOption] = []
        var seen = Set<String>()

        func add(_ width: Int, _ height: Int, note: String? = nil) {
            guard width > 0, height > 0 else { return }
            let option = ResolutionOption(width: width, height: height, note: note)
            guard seen.insert(option.id).inserted else { return }
            options.append(option)
        }

        if let screen = NSScreen.main {
            let points = screen.frame.size
            let scale = screen.backingScaleFactor
            add(Int(points.width * scale), Int(points.height * scale), note: "this display, native")
            add(Int(points.width), Int(points.height), note: "this display")
        }
        for (width, height) in [
            (3456, 2234), (3024, 1964), (2880, 1864), (2560, 1664),
            (2560, 1440), (1920, 1200), (1920, 1080), (1728, 1117),
            (1512, 982), (1470, 956), (1440, 900), (1280, 800)
        ] {
            add(width, height)
        }
        add(model.settings.width, model.settings.height)
        return options
    }

    private var displayModeCaption: String {
        switch model.settings.displayMode {
        case .borderlessFullscreen:
            return "Fills the screen as a borderless window, so switching apps with Cmd-Tab works reliably. Recommended."
        case .exclusiveFullscreen:
            return "Classic fullscreen. Switching away can leave the game unable to regain the screen; use only if borderless causes problems."
        case .windowed:
            return "A regular window at the selected resolution. Useful for setup and troubleshooting."
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
