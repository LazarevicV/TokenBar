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
        MenuBarExtra("TokenBar", systemImage: "gauge.with.dots.needle.33percent") {
            PopoverView()
        }
        .menuBarExtraStyle(.window)
    }
}
