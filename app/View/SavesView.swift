import SwiftUI

struct SavesView: View {
    @ObservedObject var model: LauncherViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    eyebrow: "PROTECTION",
                    title: "Your journey stays yours.",
                    detail: "Secunda keeps local backups separate from Steam Cloud and never overwrites saves silently."
                )

                HStack(spacing: 18) {
                    MetricPanel(value: "\(model.snapshot.saveCount)", label: "Local saves", symbol: "doc.fill")
                    MetricPanel(value: "\(model.snapshot.backupCount)", label: "Backups", symbol: "shield.fill")
                }

                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "Save protection", detail: "Local and reversible")
                    Text(model.snapshot.saveCount > 0
                         ? "Create a dated copy of every detected Skyrim save."
                         : "Saves will appear here after your first in-game save.")
                        .font(.system(size: 13))
                        .foregroundStyle(SecundaTheme.secondaryText)

                    Button("Back Up Saves Now") {
                        model.createSaveBackup()
                    }
                    .buttonStyle(SecundaSecondaryButtonStyle())
                    .disabled(model.snapshot.saveCount == 0)
                }
                .secundaPanel()
            }
            .padding(42)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }
}

struct MetricPanel: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(SecundaTheme.frost)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .medium, design: .serif))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(SecundaTheme.secondaryText)
            }
            Spacer()
        }
        .secundaPanel()
        .frame(maxWidth: .infinity)
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(SecundaTheme.frost)
            Text(title)
                .font(.system(size: 34, weight: .medium, design: .serif))
            Text(detail)
                .font(.system(size: 14))
                .foregroundStyle(SecundaTheme.secondaryText)
                .lineSpacing(4)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }
}
