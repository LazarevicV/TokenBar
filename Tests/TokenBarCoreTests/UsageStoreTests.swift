import AppKit
import Foundation
import Testing
@testable import TokenBarCore

// MARK: - Test doubles

/// Mutable state behind a `FakeProvider`, shared across concurrent fetches.
actor FakeProviderState {
    var result: Result<ProviderUsage, Error>
    var calls = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var blocked = false

    init(result: Result<ProviderUsage, Error>) {
        self.result = result
    }

    func set(_ result: Result<ProviderUsage, Error>) {
        self.result = result
    }

    /// Makes subsequent fetches wait until `release()` is called.
    func block() { blocked = true }

    func release() {
        blocked = false
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }

    func fetch() async throws -> ProviderUsage {
        calls += 1
        if blocked {
            await withCheckedContinuation { waiters.append($0) }
        }
        return try result.get()
    }
}

struct FakeProvider: UsageProvider {
    let id: ProviderID
    let displayName: String
    let state: FakeProviderState

    init(id: ProviderID, displayName: String? = nil, result: Result<ProviderUsage, Error>) {
        self.id = id
        self.displayName = displayName ?? id.rawValue.capitalized
        self.state = FakeProviderState(result: result)
    }

    func fetch() async throws -> ProviderUsage {
        try await state.fetch()
    }
}

/// Records the intervals the store sleeps for and ends the loop after `limit` sleeps.
actor SleepRecorder {
    var intervals: [TimeInterval] = []
    let limit: Int

    init(limit: Int) { self.limit = limit }

    func record(_ interval: TimeInterval) throws {
        intervals.append(interval)
        if intervals.count >= limit { throw CancellationError() }
    }
}

func usage(_ id: ProviderID, session: Double?, weekly: Double? = nil) -> ProviderUsage {
    let reset = Date(timeIntervalSince1970: 1_789_313_353)
    return ProviderUsage(
        provider: id,
        session: session.map { UsageWindow(percent: $0, resetsAt: reset, label: "5h") },
        weekly: weekly.map { UsageWindow(percent: $0, resetsAt: reset, label: "week") },
        plan: "pro"
    )
}

@MainActor
func makeSettings() -> (Settings, UserDefaults, String) {
    let name = "tokenbar.tests.store.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (Settings(defaults: defaults), defaults, name)
}

/// Polls until `condition` holds or the timeout elapses.
@MainActor
func eventually(timeout: TimeInterval = 2, _ condition: @escaping @MainActor () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return await condition()
}

// MARK: - BackoffPolicy

struct BackoffPolicyTests {
    @Test func noFailuresReturnsBase() {
        let policy = BackoffPolicy()
        #expect(policy.interval(base: 60) == 60)
        #expect(policy.isBackingOff == false)
    }

    @Test func doublesPerFailureUpToCap() {
        var policy = BackoffPolicy()
        var seen: [TimeInterval] = []
        for _ in 0..<6 {
            policy.recordFailure()
            seen.append(policy.interval(base: 60))
        }
        #expect(seen == [120, 240, 480, 600, 600, 600])
        #expect(policy.consecutiveFailures == 6)
    }

    @Test func resetsOnSuccess() {
        var policy = BackoffPolicy()
        policy.recordFailure()
        policy.recordFailure()
        policy.recordSuccess()
        #expect(policy.interval(base: 30) == 30)
        #expect(policy.isBackingOff == false)
    }

    @Test func neverBelowBaseEvenIfCapIsSmaller() {
        var policy = BackoffPolicy(maxInterval: 10)
        policy.recordFailure()
        #expect(policy.interval(base: 60) == 60)
    }

    @Test func manyFailuresDoNotOverflow() {
        var policy = BackoffPolicy()
        for _ in 0..<2_000 { policy.recordFailure() }
        #expect(policy.interval(base: 300) == 600)
    }

    @Test func classifiesErrors() {
        #expect(BackoffPolicy.shouldBackOff(ProviderError.http(429)))
        #expect(BackoffPolicy.shouldBackOff(ProviderError.http(500)))
        #expect(BackoffPolicy.shouldBackOff(ProviderError.http(503)))
        #expect(!BackoffPolicy.shouldBackOff(ProviderError.http(404)))
        #expect(!BackoffPolicy.shouldBackOff(ProviderError.http(401)))
        #expect(!BackoffPolicy.shouldBackOff(ProviderError.network("timeout")))
        #expect(!BackoffPolicy.shouldBackOff(ProviderError.tokenExpired))
        #expect(!BackoffPolicy.shouldBackOff(CancellationError()))
    }
}

// MARK: - UsageStore

@MainActor
struct UsageStoreTests {
    @Test func initialStatusesAreLoadingForEnabledProviders() {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.enabledProviders = [.claude]
        let claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 10)))
        let codex = FakeProvider(id: .codex, result: .success(usage(.codex, session: 20)))
        let store = UsageStore(providers: [claude, codex], settings: settings, sleeper: { _ in })
        #expect(store.statuses == [.claude: .loading])
        #expect(store.lastUpdated == nil)
        #expect(store.isRefreshing == false)
    }

    @Test func refreshFetchesAllAndFailsIndependently() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 68, weekly: 41)))
        let codex = FakeProvider(id: .codex, result: .failure(ProviderError.network("offline")))
        let fixedNow = Date(timeIntervalSince1970: 1_000)
        let store = UsageStore(providers: [claude, codex], settings: settings, now: { fixedNow }, sleeper: { _ in })

        await store.refreshAll()

        #expect(store.statuses[.claude] == .ok(usage(.claude, session: 68, weekly: 41)))
        #expect(store.statuses[.codex] == .error("Offline: offline"))
        #expect(store.lastUpdated == fixedNow)
        #expect(store.isRefreshing == false)
        #expect(store.lastGood[.claude] == LastGood(usage: usage(.claude, session: 68, weekly: 41), at: fixedNow))
        #expect(store.lastGood[.codex] == nil)
        #expect(await claude.state.calls == 1)
        #expect(await codex.state.calls == 1)
    }

    @Test func mapsProviderErrorsToStatuses() async {
        let cases: [(ProviderError, ProviderStatus)] = [
            (.notLoggedIn("no keychain item"), .notLoggedIn),
            (.tokenExpired, .tokenExpired),
            (.network("timeout"), .error("Offline: timeout")),
            (.network(""), .error("Offline")),
            (.http(429), .error("Rate limited (HTTP 429)")),
            (.http(503), .error("HTTP 503")),
            (.decoding("missing rate_limit"), .error("Unexpected response: missing rate_limit")),
        ]
        for (error, expected) in cases {
            #expect(UsageStore.status(for: error) == expected)
        }
        struct Other: Error {}
        if case .error = UsageStore.status(for: Other()) {} else {
            Issue.record("non-ProviderError should map to .error")
        }
    }

    @Test func keepsLastGoodAcrossFailure() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.enabledProviders = [.claude]
        let claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 30)))
        var clock = Date(timeIntervalSince1970: 100)
        let store = UsageStore(providers: [claude], settings: settings, now: { clock }, sleeper: { _ in })

        await store.refreshAll()
        #expect(store.displayUsage(for: .claude) == usage(.claude, session: 30))
        #expect(store.isStale(.claude) == false)

        clock = Date(timeIntervalSince1970: 200)
        await claude.state.set(.failure(ProviderError.http(500)))
        await store.refreshAll()

        #expect(store.statuses[.claude] == .error("HTTP 500"))
        #expect(store.lastGood[.claude]?.usage == usage(.claude, session: 30))
        #expect(store.lastGood[.claude]?.at == Date(timeIntervalSince1970: 100))
        #expect(store.displayUsage(for: .claude) == usage(.claude, session: 30))
        #expect(store.isStale(.claude) == true)
        #expect(store.lastUpdated == Date(timeIntervalSince1970: 200))
        #expect(store.highestSessionPercent == nil)
    }

    @Test func coalescesConcurrentRefreshes() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.enabledProviders = [.claude]
        let claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 5)))
        await claude.state.block()
        let store = UsageStore(providers: [claude], settings: settings, sleeper: { _ in })

        let first = Task { await store.refreshAll() }
        let second = Task { await store.refreshAll() }
        let third = Task { await store.refreshAll() }

        let started = await eventually { await claude.state.calls == 1 }
        #expect(started)
        #expect(store.isRefreshing == true)
        await claude.state.release()
        await first.value
        await second.value
        await third.value

        #expect(await claude.state.calls == 1)
        #expect(store.isRefreshing == false)
        #expect(store.statuses[.claude] == .ok(usage(.claude, session: 5)))

        // A refresh after the first completed starts a new fetch.
        await store.refreshAll()
        #expect(await claude.state.calls == 2)
    }

    @Test func honoursEnabledProviders() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let claude = FakeProvider(id: .claude, displayName: "Claude", result: .success(usage(.claude, session: 1)))
        let codex = FakeProvider(id: .codex, displayName: "Codex", result: .success(usage(.codex, session: 2)))
        let store = UsageStore(providers: [codex, claude], settings: settings, sleeper: { _ in })

        #expect(store.orderedProviders.map(\.id) == [.codex, .claude])
        #expect(store.orderedProviders.map(\.displayName) == ["Codex", "Claude"])

        settings.enabledProviders = [.claude]
        #expect(store.orderedProviders.map(\.id) == [.claude])

        await store.refreshAll()
        #expect(store.statuses.keys.sorted { $0.rawValue < $1.rawValue } == [.claude])
        #expect(await claude.state.calls == 1)
        #expect(await codex.state.calls == 0)

        // Re-enabling a provider picks it up on the next refresh without restarting.
        settings.enabledProviders = [.claude, .codex]
        await store.refreshAll()
        #expect(store.statuses[.codex] == .ok(usage(.codex, session: 2)))
        #expect(await codex.state.calls == 1)
    }

    @Test func highestSessionPercentUsesOnlyOkStatuses() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 68)))
        let codex = FakeProvider(id: .codex, result: .success(usage(.codex, session: 53)))
        let store = UsageStore(providers: [claude, codex], settings: settings, sleeper: { _ in })
        #expect(store.highestSessionPercent == nil)

        await store.refreshAll()
        #expect(store.highestSessionPercent == 68)

        await claude.state.set(.failure(ProviderError.tokenExpired))
        await store.refreshAll()
        #expect(store.highestSessionPercent == 53)

        await codex.state.set(.success(usage(.codex, session: nil, weekly: 90)))
        await store.refreshAll()
        #expect(store.highestSessionPercent == nil)
    }

    @Test func menuBarSessionRemainingHonoursChoiceAndOkStatuses() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 68)))
        let codex = FakeProvider(id: .codex, result: .success(usage(.codex, session: 53)))
        let store = UsageStore(providers: [claude, codex], settings: settings, sleeper: { _ in })
        for choice in MenuBarProvider.allCases {
            #expect(store.menuBarSessionRemaining(for: choice) == nil)
        }

        await store.refreshAll()
        #expect(store.menuBarSessionRemaining(for: .lowestRemaining) == 32)
        #expect(store.menuBarSessionRemaining(for: .claude) == 32)
        #expect(store.menuBarSessionRemaining(for: .codex) == 47)

        // A failed provider drops out of "lowest" and yields nil when chosen explicitly.
        await claude.state.set(.failure(ProviderError.tokenExpired))
        await store.refreshAll()
        #expect(store.menuBarSessionRemaining(for: .lowestRemaining) == 47)
        #expect(store.menuBarSessionRemaining(for: .claude) == nil)
        #expect(store.menuBarSessionRemaining(for: .codex) == 47)

        // Over-limit usage clamps to 0 % left; a provider without a session window contributes nothing.
        await claude.state.set(.success(usage(.claude, session: 120)))
        await codex.state.set(.success(usage(.codex, session: nil, weekly: 90)))
        await store.refreshAll()
        #expect(store.menuBarSessionRemaining(for: .lowestRemaining) == 0)
        #expect(store.menuBarSessionRemaining(for: .claude) == 0)
        #expect(store.menuBarSessionRemaining(for: .codex) == nil)
    }

    @Test func backsOffOnRateLimitAndResetsOnSuccess() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let claude = FakeProvider(id: .claude, result: .failure(ProviderError.http(429)))
        let codex = FakeProvider(id: .codex, result: .success(usage(.codex, session: 1)))
        let store = UsageStore(providers: [claude, codex], settings: settings, sleeper: { _ in })
        #expect(store.currentInterval == 60)

        await store.refreshAll()
        #expect(store.backoff.consecutiveFailures == 1)
        #expect(store.currentInterval == 120)

        await store.refreshAll()
        #expect(store.currentInterval == 240)

        // Non-backoff errors (401, offline) do not extend the delay; they reset it.
        await claude.state.set(.failure(ProviderError.tokenExpired))
        await store.refreshAll()
        #expect(store.backoff.consecutiveFailures == 0)
        #expect(store.currentInterval == 60)
    }

    @Test func currentIntervalRespectsPopoverAndMinimum() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.refreshInterval = 300
        let claude = FakeProvider(id: .claude, result: .failure(ProviderError.http(503)))
        let store = UsageStore(providers: [claude], settings: settings, sleeper: { _ in })
        #expect(store.currentInterval == 300)

        store.setPopoverOpen(true)
        #expect(store.currentInterval == 15)

        await store.refreshAll()
        #expect(store.currentInterval == 30)
        await store.refreshAll()
        #expect(store.currentInterval == 60)

        store.setPopoverOpen(false)
        #expect(store.currentInterval == 600)
    }

    @Test func loopRefreshesThenSleepsForConfiguredInterval() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.enabledProviders = [.claude]
        let claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 1)))
        let recorder = SleepRecorder(limit: 3)
        let store = UsageStore(
            providers: [claude],
            settings: settings,
            sleeper: { try await recorder.record($0) },
            wakeNotificationCenter: NotificationCenter()
        )

        store.start()
        #expect(store.isRunning)
        let done = await eventually { await recorder.intervals.count == 3 }
        #expect(done)
        store.stop()
        #expect(store.isRunning == false)

        #expect(await recorder.intervals == [60, 60, 60])
        #expect(await claude.state.calls == 3)
        #expect(store.statuses[.claude] == .ok(usage(.claude, session: 1)))
    }

    @Test func loopReReadsSettingsAndBacksOff() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.enabledProviders = [.claude]
        settings.refreshInterval = 30
        let claude = FakeProvider(id: .claude, result: .failure(ProviderError.http(429)))
        let recorder = SleepRecorder(limit: 3)
        let store = UsageStore(
            providers: [claude],
            settings: settings,
            sleeper: { try await recorder.record($0) },
            wakeNotificationCenter: NotificationCenter()
        )

        store.start()
        let done = await eventually { await recorder.intervals.count == 3 }
        #expect(done)
        store.stop()

        #expect(await recorder.intervals == [60, 120, 240])
    }

    @Test func openingPopoverRestartsLoopWithShortInterval() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.enabledProviders = [.claude]
        let claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 1)))
        let recorder = SleepRecorder(limit: 3)
        let store = UsageStore(
            providers: [claude],
            settings: settings,
            sleeper: { interval in
                try await recorder.record(interval)
                // Park until cancelled; the popover open restarts the loop.
                while !Task.isCancelled { try await Task.sleep(nanoseconds: 1_000_000) }
                throw CancellationError()
            },
            wakeNotificationCenter: NotificationCenter()
        )

        store.start()
        let firstSleep = await eventually { await recorder.intervals.count == 1 }
        #expect(firstSleep)

        store.setPopoverOpen(true)
        let refetched = await eventually { await claude.state.calls == 2 }
        #expect(refetched)
        let secondSleep = await eventually { await recorder.intervals.count == 2 }
        #expect(secondSleep)
        store.stop()

        #expect(await recorder.intervals == [60, 15])
    }

    @Test func wakeNotificationTriggersRefresh() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.enabledProviders = [.claude]
        let claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 1)))
        let center = NotificationCenter()
        let store = UsageStore(
            providers: [claude],
            settings: settings,
            sleeper: { _ in
                while !Task.isCancelled { try await Task.sleep(nanoseconds: 1_000_000) }
                throw CancellationError()
            },
            wakeNotificationCenter: center
        )

        store.start()
        // Wait for the initial refresh to fully finish; otherwise the wake refresh is
        // (correctly) coalesced onto it and no second fetch happens.
        let initial = await eventually {
            await claude.state.calls == 1 && !store.isRefreshing
        }
        #expect(initial)

        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        let woke = await eventually { await claude.state.calls == 2 }
        #expect(woke)

        store.stop()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await claude.state.calls == 2)
    }
}
