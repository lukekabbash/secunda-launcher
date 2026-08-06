import SwiftUI
import Darwin

@main
struct SecundaLauncherApp: App {
    @StateObject private var model: LauncherViewModel

    init() {
        if CommandLine.arguments.contains("--self-test") {
            Darwin.exit(SelfCheck.run())
        }
        _model = StateObject(wrappedValue: LauncherViewModel.live())
    }

    var body: some Scene {
        WindowGroup {
            LauncherRootView(model: model)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("Refresh Status") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
