import AppKit
import Foundation
import TokenBarCore

/// `Settings` clashes with SwiftUI's `Settings` scene in files that import SwiftUI; this file does not.
typealias AppSettings = Settings

/// App-lifetime holder for the single `Settings` and `UsageStore` instances.
/// Both are `@Observable`, so views read them directly.
@MainActor
final class AppModel {
    let settings: AppSettings
    let store: UsageStore

    /// Set `TOKENBAR_DEBUG_DUMP=1` to print a token-free status summary after the first refresh.
    static var debugDumpEnabled: Bool {
        ProcessInfo.processInfo.environment["TOKENBAR_DEBUG_DUMP"] == "1"
    }

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.store = UsageStore(providers: [ClaudeProvider(), CodexProvider()], settings: settings)
    }

    func start() {
        store.start()
        if Self.debugDumpEnabled {
            Task { [store] in
                await store.refreshAll()
                print(DebugDump.render(store: store))
                fflush(stdout)
            }
        }
    }

    /// Popover sections, showing last-good data with a stale caption when a refresh failed.
    var sections: [ProviderSection] {
        let formatter = ResetFormatter()
        return store.orderedProviders.map { provider in
            let status = store.status(for: provider.id) ?? .loading
            if case .error(let message) = status, let lastGood = store.lastGood[provider.id] {
                return ProviderSection(
                    id: provider.id,
                    displayName: provider.displayName,
                    status: .ok(lastGood.usage),
                    staleMessage: "\(message) · showing data from \(formatter.relativeAge(since: lastGood.at))"
                )
            }
            return ProviderSection(id: provider.id, displayName: provider.displayName, status: status)
        }
    }

    func refresh() {
        Task { await store.refreshAll() }
    }

    /// Action button in a provider section: Retry on errors, open the CLI in Terminal otherwise.
    func performAction(for id: ProviderID) {
        switch store.status(for: id) {
        case .notLoggedIn?, .tokenExpired?:
            Self.openTerminal(running: id.rawValue)
        default:
            refresh()
        }
    }

    /// Opens Terminal and runs `command` in a new tab. Failures (e.g. denied Automation permission) are ignored.
    static func openTerminal(running command: String) {
        // Only known CLI names reach here; guard anyway so nothing unexpected is interpolated into the script.
        guard command.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return }
        let source = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        // `error` is intentionally not logged.
    }
}

/// Renders the store's state without any secrets: percentages, labels, reset dates, plan and status kind.
enum DebugDump {
    @MainActor
    static func render(store: UsageStore) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["TOKENBAR_DEBUG_DUMP"]
        for provider in store.orderedProviders {
            let status = store.status(for: provider.id)
            lines.append("\(provider.displayName): \(kind(status))")
            guard case .ok(let usage)? = status else { continue }
            lines.append("  plan: \(usage.plan ?? "-")")
            for (name, window) in [("session", usage.session), ("weekly", usage.weekly)] {
                guard let window else {
                    lines.append("  \(name): none")
                    continue
                }
                lines.append("  \(name): \(Int(window.percent.rounded()))% label=\(window.label) resets=\(iso.string(from: window.resetsAt))")
            }
            if !usage.extras.isEmpty {
                lines.append("  extras: \(usage.extras.count) line(s)")
            }
        }
        if let lastUpdated = store.lastUpdated {
            lines.append("updated: \(iso.string(from: lastUpdated))")
        }
        let glyphs = store.orderedProviders.map { "\($0.id.rawValue)=\(ProviderGlyph.image(for: $0.id) == nil ? "missing" : "ok")" }
        lines.append("glyphs: \(glyphs.joined(separator: " "))")
        return lines.joined(separator: "\n")
    }

    static func kind(_ status: ProviderStatus?) -> String {
        switch status {
        case .ok?: return ".ok"
        case .loading?: return ".loading"
        case .notLoggedIn?: return ".notLoggedIn"
        case .tokenExpired?: return ".tokenExpired"
        case .error(let message)?: return ".error(\(message))"
        case nil: return "none"
        }
    }
}
