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
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 12) {
                MoonMark(size: 35)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SECUNDA")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .tracking(2.3)
                    Text("WINDOWS GAMES ON MAC")
                        .font(.system(size: 8, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(SecundaTheme.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SidebarButton(
                    title: "Games",
                    symbol: "square.grid.2x2.fill",
                    isSelected: model.selection == .games
                ) {
                    select(.games)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("LIBRARY")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(SecundaTheme.secondaryText)
                    .padding(.horizontal, 12)

                ForEach(GameDescriptor.supported) { descriptor in
                    SidebarButton(
                        title: descriptor.shortTitle,
                        symbol: descriptor.symbol,
                        isSelected: model.selection == .game(descriptor.id),
                        accessory: model.snapshot.game(descriptor).state.isReady ? nil : "circle.dashed"
                    ) {
                        select(.game(descriptor.id))
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                SidebarButton(
                    title: "Launcher Settings",
                    symbol: "slider.horizontal.3",
                    isSelected: model.selection == .settings
                ) {
                    select(.settings)
                }
                SidebarButton(
                    title: "Support",
                    symbol: "waveform.path.ecg",
                    isSelected: model.selection == .support
                ) {
                    select(.support)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Unofficial launcher", systemImage: "checkmark.shield")
                Text("Each game requires your own separately purchased Steam copy.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(SecundaTheme.secondaryText)
            .lineSpacing(3)
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(width: 224)
        .background(Color.black.opacity(0.16))
    }

    private func select(_ item: SidebarItem) {
        withAnimation(.easeOut(duration: 0.16)) {
            model.selection = item
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selection {
        case .games:
            GamesGridView(model: model)
        case .game(let gameID):
            if let descriptor = GameDescriptor.descriptor(for: gameID) {
                GameDetailView(model: model, descriptor: descriptor)
                    .id(descriptor.id)
            } else {
                GamesGridView(model: model)
            }
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
    let title: String
    let symbol: String
    let isSelected: Bool
    var accessory: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 18)
                Text(title)
                Spacer()
                if let accessory {
                    Image(systemName: accessory)
                        .font(.system(size: 9))
                        .foregroundStyle(SecundaTheme.secondaryText.opacity(0.7))
                }
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
