import AppKit
import SwiftUI
import TokenBarCore

@main
struct TokenBarApp: App {
    init() {
        // SPM executables have no LSUIElement; hide the Dock icon at runtime too.
        NSApp?.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            // Static sample data until UsageStore (built on another branch) is wired in.
            PopoverView(
                sections: SampleData.sections,
                lastUpdated: SampleData.now,
                isRefreshing: false,
                onRefresh: {},
                onOpenSettings: {},
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        } label: {
            MenuBarLabel(highestSessionPercent: 68, showPercent: true)
        }
        .menuBarExtraStyle(.window)
    }
}
