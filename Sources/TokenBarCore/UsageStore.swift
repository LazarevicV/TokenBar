import AppKit
import Foundation
import Observation

// MARK: - BackoffPolicy

/// Pure exponential-backoff bookkeeping for the refresh loop (PLAN.md §7).
///
/// After each refresh cycle call `recordFailure()` if any provider returned a
/// rate-limit or server error, otherwise `recordSuccess()`. The next sleep is
/// `interval(base:)`: `base × 2^failures`, capped at `maxInterval`.
public struct BackoffPolicy: Equatable, Sendable {
    public static let defaultMaxInterval: TimeInterval = 600

    public var maxInterval: TimeInterval
    public private(set) var consecutiveFailures: Int

    public init(maxInterval: TimeInterval = BackoffPolicy.defaultMaxInterval, consecutiveFailures: Int = 0) {
        self.maxInterval = maxInterval
        self.consecutiveFailures = consecutiveFailures
    }

    public var isBackingOff: Bool { consecutiveFailures > 0 }

    public mutating func recordFailure() {
        consecutiveFailures += 1
    }

    public mutating func recordSuccess() {
        consecutiveFailures = 0
    }

    /// The interval to sleep before the next refresh given the configured base.
    public func interval(base: TimeInterval) -> TimeInterval {
        guard consecutiveFailures > 0 else { return base }
        // Cap the exponent so `pow` cannot overflow to infinity for long outages.
        let exponent = Double(min(consecutiveFailures, 30))
        return min(base * pow(2, exponent), max(base, maxInterval))
    }

    /// Whether an error should trigger backoff (HTTP 429 or any 5xx).
    public static func shouldBackOff(_ error: Error) -> Bool {
        guard case .http(let code)? = error as? ProviderError else { return false }
        return code == 429 || (500...599).contains(code)
    }
}

// MARK: - LastGood

/// The most recent successful snapshot for a provider and when it was fetched.
public struct LastGood: Equatable, Sendable {
    public let usage: ProviderUsage
    public let at: Date

    public init(usage: ProviderUsage, at: Date) {
        self.usage = usage
        self.at = at
    }
}

// MARK: - UsageStore

/// Holds the current status of every enabled provider and drives the refresh loop.
///
/// Not wired into the UI here; the app creates one instance and injects it.
@MainActor
@Observable
public final class UsageStore {
    /// Sleeps for the given number of seconds; throws when cancelled.
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    /// Minimum polling interval; both endpoints are unofficial (PLAN.md §7).
    public static let minimumInterval: TimeInterval = 15
    /// Interval used while the popover is open.
    public static let popoverOpenInterval: TimeInterval = 15

    public private(set) var statuses: [ProviderID: ProviderStatus] = [:]
    public private(set) var lastGood: [ProviderID: LastGood] = [:]
    public private(set) var lastUpdated: Date?
    public private(set) var isRefreshing = false
    public private(set) var backoff = BackoffPolicy()
    public private(set) var isPopoverOpen = false

    @ObservationIgnored private let providers: [any UsageProvider]
    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleeper: Sleeper
    @ObservationIgnored private let wakeCenter: NotificationCenter

    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - providers: all known providers, in display order.
    ///   - settings: read on every tick so changes apply without restart.
    ///   - now: clock, injectable for tests.
    ///   - sleeper: sleep function used by the timer loop, injectable for tests.
    ///   - wakeNotificationCenter: where `NSWorkspace.didWakeNotification` is observed.
    public init(
        providers: [any UsageProvider],
        settings: Settings,
        now: @escaping () -> Date = Date.init,
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
        wakeNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.providers = providers
        self.settings = settings
        self.now = now
        self.sleeper = sleeper
        self.wakeCenter = wakeNotificationCenter
        for provider in enabledProviders {
            statuses[provider.id] = .loading
        }
    }

    // MARK: Derived state

    /// Enabled providers in the order given at init.
    public var orderedProviders: [(id: ProviderID, displayName: String)] {
        enabledProviders.map { ($0.id, $0.displayName) }
    }

    private var enabledProviders: [any UsageProvider] {
        providers.filter { settings.enabledProviders.contains($0.id) }
    }

    public func status(for id: ProviderID) -> ProviderStatus? {
        statuses[id]
    }

    /// The current usage if the last refresh succeeded, otherwise the last good snapshot.
    public func displayUsage(for id: ProviderID) -> ProviderUsage? {
        if case .ok(let usage)? = statuses[id] {
            return usage
        }
        return lastGood[id]?.usage
    }

    /// True when the shown data for `id` comes from `lastGood` rather than the current status.
    public func isStale(_ id: ProviderID) -> Bool {
        if case .ok? = statuses[id] { return false }
        return lastGood[id] != nil
    }

    /// Highest session (used) percentage across providers with an `.ok` status.
    /// Kept for compatibility; the app shows remaining via `menuBarSessionRemaining(for:)`.
    public var highestSessionPercent: Double? {
        statuses.values.compactMap { status -> Double? in
            guard case .ok(let usage) = status else { return nil }
            return usage.session?.percent
        }.max()
    }

    /// Remaining session percentage for the menu bar. `.lowestRemaining` is the minimum across
    /// providers with an `.ok` status; a specific provider yields its value only while it is `.ok`.
    public func menuBarSessionRemaining(for choice: MenuBarProvider) -> Double? {
        switch choice {
        case .lowestRemaining:
            return statuses.values.compactMap(sessionRemaining).min()
        case .claude:
            return statuses[.claude].flatMap(sessionRemaining)
        case .codex:
            return statuses[.codex].flatMap(sessionRemaining)
        }
    }

    private func sessionRemaining(_ status: ProviderStatus) -> Double? {
        guard case .ok(let usage) = status else { return nil }
        return usage.session?.remaining
    }

    /// The interval the loop will sleep before the next refresh.
    public var currentInterval: TimeInterval {
        let base = isPopoverOpen ? Self.popoverOpenInterval : settings.refreshInterval
        return max(Self.minimumInterval, backoff.interval(base: base))
    }

    // MARK: Refresh

    /// Fetches all enabled providers concurrently. Concurrent calls await the in-flight refresh.
    public func refreshAll() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await performRefresh() }
        inFlight = task
        await task.value
    }

    private func performRefresh() async {
        isRefreshing = true
        defer {
            // Cleared together with `isRefreshing` so the two never disagree.
            isRefreshing = false
            inFlight = nil
        }

        let targets = enabledProviders
        let results = await withTaskGroup(of: (ProviderID, Result<ProviderUsage, Error>).self) { group in
            for provider in targets {
                group.addTask {
                    do {
                        return (provider.id, .success(try await provider.fetch()))
                    } catch {
                        return (provider.id, .failure(error))
                    }
                }
            }
            var collected: [ProviderID: Result<ProviderUsage, Error>] = [:]
            for await (id, result) in group {
                collected[id] = result
            }
            return collected
        }

        let timestamp = now()
        var newStatuses: [ProviderID: ProviderStatus] = [:]
        var shouldBackOff = false
        for provider in targets {
            guard let result = results[provider.id] else { continue }
            switch result {
            case .success(let usage):
                newStatuses[provider.id] = .ok(usage)
                lastGood[provider.id] = LastGood(usage: usage, at: timestamp)
            case .failure(let error):
                newStatuses[provider.id] = Self.status(for: error)
                if BackoffPolicy.shouldBackOff(error) { shouldBackOff = true }
            }
        }
        statuses = newStatuses
        lastUpdated = timestamp
        if shouldBackOff {
            backoff.recordFailure()
        } else {
            backoff.recordSuccess()
        }
    }

    /// Maps a provider error onto the status shown in the UI. Messages must not contain secrets.
    static func status(for error: Error) -> ProviderStatus {
        guard let providerError = error as? ProviderError else {
            return .error(error.localizedDescription)
        }
        switch providerError {
        case .notLoggedIn:
            return .notLoggedIn
        case .tokenExpired:
            return .tokenExpired
        case .network(let message):
            return .error(message.isEmpty ? "Offline" : "Offline: \(message)")
        case .http(let code):
            return .error(code == 429 ? "Rate limited (HTTP 429)" : "HTTP \(code)")
        case .decoding(let message):
            return .error(message.isEmpty ? "Unexpected response" : "Unexpected response: \(message)")
        }
    }

    // MARK: Timer loop

    /// Refreshes immediately, then keeps refreshing on `currentInterval`. Also refreshes on system wake.
    public func start() {
        startLoop()
        if wakeObserver == nil {
            wakeObserver = wakeCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshAll()
                }
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        if let wakeObserver {
            wakeCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    public var isRunning: Bool { loop != nil }

    /// While open the store polls every `popoverOpenInterval` seconds and refreshes immediately.
    public func setPopoverOpen(_ open: Bool) {
        guard open != isPopoverOpen else { return }
        isPopoverOpen = open
        if open, isRunning {
            // Restart so the pending sleep is cut short and a fresh fetch happens now.
            startLoop()
        }
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshAll()
                let interval = self.currentInterval
                do {
                    try await self.sleeper(interval)
                } catch {
                    return
                }
            }
        }
    }
}
