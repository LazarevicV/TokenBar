import AppKit
import SwiftUI
import TokenBarCore

@main
struct TokenBarApp: App {
    // The `App` instance lives for the whole process, so a plain stored property is app-lifetime.
    private let model: AppModel

    init() {
        // SPM executables have no LSUIElement; hide the Dock icon at runtime too.
        NSApp?.setActivationPolicy(.accessory)
        model = AppModel()
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            MenuBarLabel(
                sessionRemaining: model.store.menuBarSessionRemaining(for: model.settings.menuBarProvider),
                showPercent: model.settings.showPercentInMenuBar
            )
        }
        .menuBarExtraStyle(.window)

        Window("TokenBar Settings", id: "settings") {
            SettingsView(settings: model.settings, store: model.store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Hosts the popover so it can use the `openWindow` environment action and observe the store.
private struct MenuBarContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PopoverView(
            sections: model.sections,
            lastUpdated: model.store.lastUpdated,
            isRefreshing: model.store.isRefreshing,
            onRefresh: { model.refresh() },
            onOpenSettings: openSettings,
            onQuit: { NSApplication.shared.terminate(nil) },
            onAction: { model.performAction(for: $0) },
            onResetLimits: { model.confirmAndResetLimits(for: $0) }
        )
        .onAppear { model.store.setPopoverOpen(true) }
        .onDisappear { model.store.setPopoverOpen(false) }
    }

    private func openSettings() {
        openWindow(id: "settings")
        // Accessory apps do not come to the front on their own.
        NSApp.activate(ignoringOtherApps: true)
    }
}
