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
                ZStack {
                    content
                        .id(model.selection)
                        .transition(.opacity.combined(with: .offset(y: 10)))
                }
                .animation(.easeOut(duration: 0.22), value: model.selection)
            }
        }
        .foregroundStyle(SecundaTheme.text)
        .alert("Secunda couldn’t continue", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.presentedError = nil }
            Button("Open Settings") {
                model.selection = .settings
                model.presentedError = nil
            }
        } message: {
            Text(model.presentedError ?? "Unknown error")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
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
            .padding(.horizontal, 22)

            VStack(alignment: .leading, spacing: 4) {
                SidebarRow(
                    title: "Games",
                    isSelected: model.selection == .games,
                    icon: { SidebarSymbol(name: "square.grid.2x2.fill") }
                ) {
                    select(.games)
                }

                Text("LIBRARY")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(SecundaTheme.secondaryText)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 4)

                ForEach(GameDescriptor.supported) { descriptor in
                    SidebarRow(
                        title: descriptor.shortTitle,
                        subtitle: sidebarSubtitle(for: descriptor),
                        isSelected: model.selection == .game(descriptor.id),
                        forceStopTitle: "Force stop \(descriptor.shortTitle)?",
                        onForceStop: { model.forceStopGame(descriptor) },
                        icon: { SidebarGameThumb(descriptor: descriptor) }
                    ) {
                        select(.game(descriptor.id))
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(spacing: 0) {
                Rectangle()
                    .fill(SecundaTheme.hairline)
                    .frame(height: 1)
                HStack {
                    Text("v0.1 · Unofficial")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(SecundaTheme.secondaryText.opacity(0.8))
                    Spacer()
                    Button {
                        select(.settings)
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(SecundaIconButtonStyle())
                    .help("Launcher settings, support, and recovery")
                    .background {
                        if model.selection == .settings {
                            Circle().fill(Color.white.opacity(0.09))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .padding(.top, 34)
        .frame(width: 236)
        .background(Color.black.opacity(0.16))
    }

    private func sidebarSubtitle(for descriptor: GameDescriptor) -> String? {
        switch model.snapshot.game(descriptor).state {
        case .ready: nil
        case .working: nil
        default: "Not installed"
        }
    }

    private func select(_ item: SidebarItem) {
        withAnimation(.easeOut(duration: 0.18)) {
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
            } else {
                GamesGridView(model: model)
            }
        case .settings:
            SettingsView(model: model)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.presentedError != nil },
            set: { if !$0 { model.presentedError = nil } }
        )
    }
}

private struct SidebarSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 30, height: 40)
    }
}

/// Small poster thumbnail for a game row, with a symbol fallback.
private struct SidebarGameThumb: View {
    let descriptor: GameDescriptor

    var body: some View {
        Color.clear
            .frame(width: 30, height: 40)
            .overlay {
                if let url = descriptor.cardArtworkURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            fallback
                        }
                    }
                } else {
                    fallback
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(SecundaTheme.hairline)
            }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [SecundaTheme.slate, SecundaTheme.midnight],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: descriptor.symbol)
                .font(.system(size: 12))
                .foregroundStyle(SecundaTheme.frost)
        }
    }
}

/// Full-width sidebar row with a large forgiving hit area, hover state,
/// and an optional hover-revealed force-stop control for game rows.
private struct SidebarRow<Icon: View>: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    var forceStopTitle: String?
    var onForceStop: (() -> Void)?
    @ViewBuilder var icon: Icon
    let action: () -> Void

    @State private var isHovering = false
    @State private var showsStopConfirmation = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? SecundaTheme.text : SecundaTheme.secondaryText)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(SecundaTheme.secondaryText.opacity(0.7))
                    }
                }
                Spacer(minLength: 0)
                if isHovering, onForceStop != nil {
                    Button {
                        showsStopConfirmation = true
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(SecundaTheme.ember)
                            .frame(width: 22, height: 22)
                            .background {
                                Circle().fill(Color.white.opacity(0.08))
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Force stop — for hung games; skips saving")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.09 : (isHovering ? 0.05 : 0)))
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
        .confirmationDialog(
            forceStopTitle ?? "Force stop?",
            isPresented: $showsStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Force Stop", role: .destructive) {
                onForceStop?()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Immediately kills this game's processes, including hung or orphaned ones. Unsaved progress is lost.")
        }
    }
}
