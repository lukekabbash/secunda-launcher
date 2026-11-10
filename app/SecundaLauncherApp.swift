import AppKit
import SwiftUI
import Darwin

final class SecundaAppDelegate: NSObject, NSApplicationDelegate {
    var updater: AppUpdater?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let waits = updater?.prepareForQuit { allowed in
            sender.reply(toApplicationShouldTerminate: allowed)
        } ?? false
        return waits ? .terminateLater : .terminateNow
    }
}

@main
struct SecundaLauncherApp: App {
    @NSApplicationDelegateAdaptor(SecundaAppDelegate.self) private var appDelegate
    @StateObject private var model: LauncherViewModel
    @StateObject private var updater: AppUpdater

    init() {
        if CommandLine.arguments.contains("--self-test") {
            Darwin.exit(SelfCheck.run())
        }
        let model = LauncherViewModel.live()
        let updater = AppUpdater()
        updater.isGameSpaceActive = { [weak model] in
            await model?.isGameSpaceRunning() ?? false
        }
        updater.closeGameSpace = { [weak model] in
            await model?.closeGameSpaceForUpdate()
        }
        model.updater = updater
        #if DEBUG
        // Design preview: open straight to Settings in an unpackaged debug build.
        if ProcessInfo.processInfo.environment["SECUNDA_PREVIEW_SETTINGS"] != nil {
            model.selection = .settings
        }
        #endif
        _model = StateObject(wrappedValue: model)
        _updater = StateObject(wrappedValue: updater)
    }

    var body: some Scene {
        WindowGroup {
            LauncherRootView(model: model)
                .environmentObject(updater)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(.dark)
                .onAppear { appDelegate.updater = updater }
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.isAvailable || !updater.canCheckForUpdates)
                Button("Refresh Status") {
                    Task {
                        await model.refresh()
                        await model.sweepOrphanedProcesses()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
