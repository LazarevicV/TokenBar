import CoreServices
import Foundation

/// Detects that a provider's CLI is in use by watching the directories it writes session data to.
///
/// This is only an activity *trigger*: file names and contents are never read. Each root maps to a
/// `ProviderID`; any file-system event under a root marks that provider as active. Roots that do not
/// exist yet are polled every `missingRootPollInterval` seconds and watched once they appear.
@MainActor
public final class ActivityMonitor {
    /// At most one `onActivity` callback per provider within this many seconds.
    nonisolated public static let debounceInterval: TimeInterval = 2
    /// How often to check whether a missing root directory has appeared.
    nonisolated public static let missingRootPollInterval: TimeInterval = 60
    /// FSEvents coalescing latency, in seconds.
    nonisolated public static let fsEventsLatency: TimeInterval = 1

    /// Called on the main actor when activity is seen for a provider (debounced).
    public var onActivity: (@MainActor (ProviderID) -> Void)?

    public let roots: [(ProviderID, URL)]
    public private(set) var isRunning = false

    private let now: () -> Date
    private let debounce: TimeInterval
    private let pollInterval: TimeInterval
    private var watchers: [Watcher] = []
    private var pending: [(ProviderID, URL)] = []
    private var pollTask: Task<Void, Never>?
    private var lastFired: [ProviderID: Date] = [:]

    /// - Parameters:
    ///   - roots: directories to watch recursively, each tagged with the provider it belongs to.
    ///   - now: clock, injectable for tests.
    ///   - debounce: minimum seconds between two callbacks for the same provider.
    ///   - pollInterval: seconds between checks for roots that do not exist yet.
    public init(
        roots: [(ProviderID, URL)],
        now: @escaping () -> Date = Date.init,
        debounce: TimeInterval = ActivityMonitor.debounceInterval,
        pollInterval: TimeInterval = ActivityMonitor.missingRootPollInterval
    ) {
        self.roots = roots
        self.now = now
        self.debounce = debounce
        self.pollInterval = pollInterval
    }

    /// Where the CLIs write session data: Claude Code keeps transcripts under
    /// `$CLAUDE_CONFIG_DIR/projects` (default `~/.claude/projects`), Codex under
    /// `$CODEX_HOME/sessions` (default `~/.codex/sessions`).
    public static func defaultRoots(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [(ProviderID, URL)] {
        let claudeDir = environment["CLAUDE_CONFIG_DIR"].flatMap(Self.directoryURL)
            ?? home.appendingPathComponent(".claude", isDirectory: true)
        let codexDir = environment["CODEX_HOME"].flatMap(Self.directoryURL)
            ?? home.appendingPathComponent(".codex", isDirectory: true)
        return [
            (.claude, claudeDir.appendingPathComponent("projects", isDirectory: true)),
            (.codex, codexDir.appendingPathComponent("sessions", isDirectory: true)),
        ]
    }

    private static func directoryURL(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// The providers currently being watched (roots that exist).
    public var watchedProviders: [ProviderID] {
        watchers.map(\.provider)
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        pending = roots
        attachExistingRoots()
        schedulePollIfNeeded()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        watchers.forEach { $0.stop() }
        watchers = []
        pending = []
    }

    // MARK: Private

    private func attachExistingRoots() {
        var stillMissing: [(ProviderID, URL)] = []
        for (provider, url) in pending {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            guard exists, isDirectory.boolValue else {
                stillMissing.append((provider, url))
                continue
            }
            let watcher = Watcher(provider: provider, path: url.path) { [weak self] provider in
                Task { @MainActor [weak self] in self?.handleEvent(for: provider) }
            }
            if watcher.start() {
                watchers.append(watcher)
            } else {
                stillMissing.append((provider, url))
            }
        }
        pending = stillMissing
    }

    private func schedulePollIfNeeded() {
        pollTask?.cancel()
        pollTask = nil
        guard !pending.isEmpty else { return }
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
                guard let self, self.isRunning else { return }
                self.attachExistingRoots()
                if self.pending.isEmpty { return }
            }
        }
    }

    /// Feeds a synthetic event through the debounce logic. Test hook only.
    func handleEventForTesting(_ provider: ProviderID) {
        handleEvent(for: provider)
    }

    private func handleEvent(for provider: ProviderID) {
        guard isRunning else { return }
        let current = now()
        if let last = lastFired[provider], current.timeIntervalSince(last) < debounce {
            return
        }
        lastFired[provider] = current
        onActivity?(provider)
    }
}

// MARK: - Watcher

/// One FSEvents stream rooted at a directory. Callbacks arrive on a private queue and are
/// forwarded to `handler`; the handler is responsible for hopping to the main actor.
private final class Watcher: @unchecked Sendable {
    let provider: ProviderID
    private let path: String
    private let handler: @Sendable (ProviderID) -> Void
    private let queue = DispatchQueue(label: "TokenBar.ActivityMonitor")
    private var stream: FSEventStreamRef?

    init(provider: ProviderID, path: String, handler: @escaping @Sendable (ProviderID) -> Void) {
        self.provider = provider
        self.path = path
        self.handler = handler
    }

    /// Creates and starts the stream. Returns false if FSEvents refused the path.
    func start() -> Bool {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handler(watcher.provider)
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            ActivityMonitor.fsEventsLatency,
            flags
        ) else {
            return false
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
