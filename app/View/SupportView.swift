import SwiftUI

struct SupportView: View {
    @ObservedObject var model: LauncherViewModel
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    eyebrow: "RECOVERY",
                    title: "No mystery failures.",
                    detail: "Secunda keeps its runtime evidence local and gives each failure a concrete next step."
                )

                HStack(spacing: 12) {
                    Button(copied ? "Copied" : "Copy Diagnostic Report") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.diagnosticReport, forType: .string)
                        copied = true
                    }
                    .buttonStyle(SecundaSecondaryButtonStyle())

                    Button("Reveal Logs") { model.revealLogs() }
                        .buttonStyle(.plain)
                        .foregroundStyle(SecundaTheme.frost)

                    if model.snapshot.game.isReady {
                        Button("Verify Game Files") { model.verifyGameFiles() }
                            .buttonStyle(.plain)
                            .foregroundStyle(SecundaTheme.frost)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "System report", detail: "Safe to share")
                    Text(model.diagnosticReport)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SecundaTheme.secondaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .secundaPanel()

                DisclosureGroup("Latest runtime log") {
                    Text(model.latestLogExcerpt)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SecundaTheme.secondaryText)
                        .textSelection(.enabled)
                        .padding(.top, 12)
                }
                .secundaPanel()
            }
            .padding(42)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }
}
