import SwiftUI

struct LauncherRootView: View {
    @ObservedObject var model: LauncherViewModel

    var body: some View {
        ZStack {
            SecundaBackdrop()

            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(SecundaTheme.hairline)
                    .frame(width: 1)
                content
            }
        }
        .foregroundStyle(SecundaTheme.text)
        .alert("Secunda couldn’t continue", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.presentedError = nil }
            Button("Open Support") {
                model.selection = .support
                model.presentedError = nil
            }
        } message: {
            Text(model.presentedError ?? "Unknown error")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 12) {
                MoonMark(size: 35)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SECUNDA")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(2.3)
                    Text("SKYRIM ON MAC")
                        .font(.system(size: 8, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(SecundaTheme.secondaryText)
                }
            }

            VStack(spacing: 6) {
                ForEach(LauncherSection.allCases) { section in
                    SidebarButton(
                        section: section,
                        isSelected: model.selection == section
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            model.selection = section
                        }
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("Unofficial launcher", systemImage: "checkmark.shield")
                Text("Requires a separately owned Steam copy of Skyrim Special Edition.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(SecundaTheme.secondaryText)
            .lineSpacing(3)
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(width: 220)
        .background(Color.black.opacity(0.16))
    }

    @ViewBuilder
    private var content: some View {
        switch model.selection {
        case .play:
            PlayView(model: model)
        case .saves:
            SavesView(model: model)
        case .settings:
            SettingsView(model: model)
        case .support:
            SupportView(model: model)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.presentedError != nil },
            set: { if !$0 { model.presentedError = nil } }
        )
    }
}

private struct SidebarButton: View {
    let section: LauncherSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.symbol)
                    .frame(width: 18)
                Text(section.title)
                Spacer()
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? SecundaTheme.text : SecundaTheme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.085) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
