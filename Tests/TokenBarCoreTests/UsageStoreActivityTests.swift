import AppKit
import Foundation
import Testing
@testable import TokenBarCore

/// A mutable clock shareable with `@Sendable` sleepers.
final class ClockBox: @unchecked Sendable {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor
struct UsageStoreActivityTests {
    @Test func noteActivitySetsWindowAndFetchesImmediately() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.refreshInterval = 300
        var clock = Date(timeIntervalSince1970: 10_000)
        let claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 1)))
        let codex = FakeProvider(id: .codex, result: .success(usage(.codex, session: 2)))
        let store = UsageStore(providers: [claude, codex], settings: settings, now: { clock }, sleeper: { _ in })
        #expect(store.isActive(.codex) == false)
        #expect(store.activeProviders.isEmpty)
        #expect(store.currentInterval == 300)

        store.noteActivity(for: .codex)
        #expect(store.activeUntil[.codex] == clock.addingTimeInterval(300))
        #expect(store.isActive(.codex))
        #expect(store.isActive(.claude) == false)
        #expect(store.activeProviders == [.codex])
        #expect(store.currentInterval == 15, "active provider polls at its required interval (floored at 15 s)")
        let fetched = await eventually { await codex.state.calls == 1 }
        #expect(fetched)

        // The window expires without further activity.
        clock = clock.addingTimeInterval(299)
        #expect(store.isActive(.codex))
        clock = clock.addingTimeInterval(1)
        #expect(store.isActive(.codex) == false)
        #expect(store.currentInterval == 300)
    }

    @Test func activeProviderNeverPolledFasterThanItsRequiredInterval() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.enabledProviders = [.claude]
        settings.refreshInterval = 300
        var clock = Date(timeIntervalSince1970: 10_000)
        var claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 1)))
        claude.minimumRefreshInterval = 130
        let store = UsageStore(providers: [claude], settings: settings, now: { clock }, sleeper: { _ in })

        await store.refreshAll()
        #expect(await claude.state.calls == 1)

        // Activity 10 s after a fetch: the provider is not due, so no immediate fetch happens.
        clock = clock.addingTimeInterval(10)
        store.noteActivity(for: .claude)
        #expect(store.currentInterval == 130)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await claude.state.calls == 1)
    }

    @Test func refreshWhileActiveOffDisablesFastPolling() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.refreshInterval = 300
        settings.refreshWhileActive = false
        let clock = Date(timeIntervalSince1970: 10_000)
        let codex = FakeProvider(id: .codex, result: .success(usage(.codex, session: 2)))
        let store = UsageStore(providers: [codex], settings: settings, now: { clock }, sleeper: { _ in })

        store.noteActivity(for: .codex)
        #expect(store.isActive(.codex), "the active window is still tracked for display")
        #expect(store.currentInterval == 300)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await codex.state.calls == 0)
    }

    @Test func ignoresDisabledProviders() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.enabledProviders = [.claude]
        let claude = FakeProvider(id: .claude, result: .success(usage(.claude, session: 1)))
        let codex = FakeProvider(id: .codex, result: .success(usage(.codex, session: 2)))
        let store = UsageStore(providers: [claude, codex], settings: settings, sleeper: { _ in })

        store.noteActivity(for: .codex)
        #expect(store.isActive(.codex) == false)
        #expect(store.activeProviders.isEmpty)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await codex.state.calls == 0)
        #expect(await claude.state.calls == 0)
    }

    @Test func loopUsesActiveIntervalUntilWindowElapses() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.enabledProviders = [.codex]
        settings.refreshInterval = 300
        let clock = ClockBox(Date(timeIntervalSince1970: 10_000))
        let codex = FakeProvider(id: .codex, result: .success(usage(.codex, session: 2)))
        let recorder = SleepRecorder(limit: 22)
        let store = UsageStore(
            providers: [codex],
            settings: settings,
            now: { clock.date },
            sleeper: { interval in
                // Simulated time: sleeping advances the clock by the requested interval.
                clock.date = clock.date.addingTimeInterval(interval)
                try await recorder.record(interval)
            },
            wakeNotificationCenter: NotificationCenter()
        )

        store.noteActivity(for: .codex)
        store.start()
        let done = await eventually { await recorder.intervals.count == 22 }
        #expect(done)
        store.stop()

        // 300 s window / 15 s = 20 fast ticks, then back to the configured 5 min.
        let expected = Array(repeating: TimeInterval(15), count: 20) + [300, 300]
        #expect(await recorder.intervals == expected)
    }

    @Test func noteActivityWakesSleepingLoop() async {
        let (settings, defaults, name) = makeSettings()
        defer { defaults.removePersistentDomain(forName: name) }
        settings.enabledProviders = [.codex]
        settings.refreshInterval = 300
        let codex = FakeProvider(id: .codex, result: .success(usage(.codex, session: 2)))
        let recorder = SleepRecorder(limit: 3)
        let store = UsageStore(
            providers: [codex],
            settings: settings,
            sleeper: { interval in
                try await recorder.record(interval)
                // Park until cancelled; noteActivity restarts the loop.
                while !Task.isCancelled { try await Task.sleep(nanoseconds: 1_000_000) }
                throw CancellationError()
            },
            wakeNotificationCenter: NotificationCenter()
        )

        store.start()
        let firstSleep = await eventually { await recorder.intervals.count == 1 }
        #expect(firstSleep)
        #expect(await codex.state.calls == 1)

        store.noteActivity(for: .codex)
        let refetched = await eventually { await codex.state.calls == 2 }
        #expect(refetched)
        let secondSleep = await eventually { await recorder.intervals.count == 2 }
        #expect(secondSleep)
        store.stop()

        #expect(await recorder.intervals == [300, 15])
    }
}
