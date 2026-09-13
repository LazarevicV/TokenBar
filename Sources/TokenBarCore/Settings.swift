import Foundation
import Observation
import ServiceManagement

/// User-facing preferences, persisted in `UserDefaults` under `tokenbar.`-prefixed keys.
///
/// The defaults suite is injectable so tests can use a throwaway suite.
@MainActor
@Observable
public final class Settings {
    public enum Keys {
        public static let refreshInterval = "tokenbar.refreshInterval"
        public static let showPercentInMenuBar = "tokenbar.showPercentInMenuBar"
        public static let enabledProviders = "tokenbar.enabledProviders"
    }

    /// Refresh intervals offered in the UI, in seconds.
    public static let allowedRefreshIntervals: [TimeInterval] = [30, 60, 300]
    public static let defaultRefreshInterval: TimeInterval = 60
    public static let defaultEnabledProviders: Set<ProviderID> = [.claude, .codex]

    @ObservationIgnored private let defaults: UserDefaults

    /// Seconds between automatic refreshes while the popover is closed.
    /// Values outside `allowedRefreshIntervals` snap to the nearest allowed value.
    public var refreshInterval: TimeInterval {
        didSet {
            let snapped = Settings.snap(refreshInterval)
            if snapped != refreshInterval {
                refreshInterval = snapped
                return
            }
            defaults.set(refreshInterval, forKey: Keys.refreshInterval)
        }
    }

    /// Show the highest session percentage next to the menu bar icon.
    public var showPercentInMenuBar: Bool {
        didSet { defaults.set(showPercentInMenuBar, forKey: Keys.showPercentInMenuBar) }
    }

    /// Providers the user wants polled and shown.
    public var enabledProviders: Set<ProviderID> {
        didSet {
            defaults.set(enabledProviders.map(\.rawValue).sorted(), forKey: Keys.enabledProviders)
        }
    }

    /// Last error from registering/unregistering launch at login, if any.
    public private(set) var launchAtLoginError: String?

    /// Whether the app is registered to launch at login (`SMAppService.mainApp`).
    /// The status is read from the system on every access; setting it registers or
    /// unregisters and records any failure in `launchAtLoginError` instead of throwing.
    public var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = error.localizedDescription
                }
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.refreshInterval) != nil {
            refreshInterval = Settings.snap(defaults.double(forKey: Keys.refreshInterval))
        } else {
            refreshInterval = Settings.defaultRefreshInterval
        }

        if defaults.object(forKey: Keys.showPercentInMenuBar) != nil {
            showPercentInMenuBar = defaults.bool(forKey: Keys.showPercentInMenuBar)
        } else {
            showPercentInMenuBar = true
        }

        if let raw = defaults.stringArray(forKey: Keys.enabledProviders) {
            enabledProviders = Set(raw.map(ProviderID.init(rawValue:)))
        } else {
            enabledProviders = Settings.defaultEnabledProviders
        }
    }

    public func isEnabled(_ id: ProviderID) -> Bool {
        enabledProviders.contains(id)
    }

    public func setEnabled(_ id: ProviderID, _ enabled: Bool) {
        if enabled {
            enabledProviders.insert(id)
        } else {
            enabledProviders.remove(id)
        }
    }

    /// Snaps an arbitrary interval to the nearest allowed value.
    static func snap(_ interval: TimeInterval) -> TimeInterval {
        guard !allowedRefreshIntervals.contains(interval) else { return interval }
        return allowedRefreshIntervals.min { abs($0 - interval) < abs($1 - interval) }
            ?? defaultRefreshInterval
    }
}
