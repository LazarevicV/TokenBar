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

    /// Asks for confirmation, then redeems one Codex rate-limit reset credit and refreshes.
    /// Uses `NSAlert` so the confirmation does not depend on popover/SwiftUI state.
    func confirmAndResetLimits(for id: ProviderID = .codex) {
        guard id == .codex, !isResettingLimits else { return }
        let available: Int
        if case .ok(let usage)? = store.status(for: id), let count = usage.resetCreditsAvailable {
            available = count
        } else if let usage = store.lastGood[id]?.usage, let count = usage.resetCreditsAvailable {
            available = count
        } else {
            available = 0
        }
        guard available > 0 else {
            Self.showAlert(title: "No reset credits", message: "Your account has no Codex reset credits to redeem.")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Reset Codex rate limits?"
        let credits = available == 1 ? "your last reset credit" : "one of your \(available) reset credits"
        alert.informativeText = "This redeems \(credits) and resets both the 5-hour and weekly windows. This cannot be undone."
        alert.addButton(withTitle: "Reset limits")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        isResettingLimits = true
        Task { [store] in
            defer { isResettingLimits = false }
            do {
                _ = try await CodexResetService().redeemFirstAvailable()
                // Give the backend a moment to apply the reset before re-reading usage.
                try? await Task.sleep(for: .seconds(2))
                await store.refreshAll()
            } catch {
                Self.showAlert(title: "Could not reset Codex limits", message: Self.describe(error))
            }
        }
    }

    private(set) var isResettingLimits = false

    /// Short, secret-free error text for the failure alert.
    static func describe(_ error: Error) -> String {
        switch error {
        case ProviderError.tokenExpired: return "Session expired. Run `codex` once to refresh the token, then try again."
        case ProviderError.notLoggedIn(let message): return message
        case ProviderError.network(let message): return message
        case ProviderError.http(let status): return "Codex returned HTTP \(status)."
        case ProviderError.decoding(let message): return message
        case let error as CodexResetError: return error.errorDescription ?? "No reset credit available."
        case is CancellationError: return "The request was cancelled."
        default: return "Unexpected error (\(type(of: error)))."
        }
    }

    static func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
            if let credits = usage.resetCreditsAvailable {
                lines.append("  resetCredits: \(credits)")
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
