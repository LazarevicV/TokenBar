import Foundation
import Testing
@testable import TokenBarCore

/// Collects activity callbacks on the main actor.
@MainActor
final class ActivityRecorder {
    var events: [ProviderID] = []
}

@MainActor
struct ActivityMonitorTests {
    nonisolated private static var isCI: Bool { ProcessInfo.processInfo.environment["CI"] != nil }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenbar-activity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func defaultRootsHonourEnvironmentOverrides() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let plain = ActivityMonitor.defaultRoots(environment: [:], home: home)
        #expect(plain.map(\.0) == [.claude, .codex])
        #expect(plain[0].1.path == "/Users/example/.claude/projects")
        #expect(plain[1].1.path == "/Users/example/.codex/sessions")

        let overridden = ActivityMonitor.defaultRoots(
            environment: ["CLAUDE_CONFIG_DIR": "/tmp/cc", "CODEX_HOME": "/tmp/cx"],
            home: home
        )
        #expect(overridden[0].1.path == "/tmp/cc/projects")
        #expect(overridden[1].1.path == "/tmp/cx/sessions")
    }

    @Test func startOnlyWatchesExistingRoots() throws {
        let present = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: present) }
        let missing = present.appendingPathComponent("missing", isDirectory: true)
        let monitor = ActivityMonitor(roots: [(.claude, present), (.codex, missing)], pollInterval: 3_600)

        monitor.start()
        #expect(monitor.isRunning)
        #expect(monitor.watchedProviders == [.claude])
        monitor.stop()
        #expect(monitor.isRunning == false)
        #expect(monitor.watchedProviders.isEmpty)
    }

    @Test(.enabled(if: !ActivityMonitorTests.isCI, "FSEvents is not reliable on CI runners"))
    func writingAFileTriggersCallback() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = ActivityRecorder()
        let monitor = ActivityMonitor(roots: [(.codex, root)])
        monitor.onActivity = { recorder.events.append($0) }
        monitor.start()
        defer { monitor.stop() }

        let nested = root.appendingPathComponent("2026/09/13", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: nested.appendingPathComponent("rollout.jsonl"))

        let fired = await eventually(timeout: 5) { recorder.events.contains(.codex) }
        #expect(fired)
    }

    @Test func debouncesCallbacksPerProvider() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let recorder = ActivityRecorder()
        let monitor = ActivityMonitor(roots: [], now: { clock }, debounce: 2)
        monitor.onActivity = { recorder.events.append($0) }
        monitor.start()

        monitor.handleEventForTesting(.claude)
        monitor.handleEventForTesting(.claude)
        monitor.handleEventForTesting(.codex)
        #expect(recorder.events == [.claude, .codex])

        clock = clock.addingTimeInterval(1.5)
        monitor.handleEventForTesting(.claude)
        #expect(recorder.events == [.claude, .codex])

        clock = clock.addingTimeInterval(1)
        monitor.handleEventForTesting(.claude)
        #expect(recorder.events == [.claude, .codex, .claude])

        monitor.stop()
        monitor.handleEventForTesting(.codex)
        #expect(recorder.events == [.claude, .codex, .claude])
    }
}
