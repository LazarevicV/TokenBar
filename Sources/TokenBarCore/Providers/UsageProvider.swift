import Foundation

/// A source of rate-limit usage for one account (Claude, Codex, …).
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    /// Reads credentials fresh and fetches the current usage snapshot.
    func fetch() async throws -> ProviderUsage
    /// Minimum seconds between two fetches of this provider. The store never polls faster,
    /// regardless of the user's refresh interval. Defaults to 15 s.
    var minimumRefreshInterval: TimeInterval { get }
}

public extension UsageProvider {
    var minimumRefreshInterval: TimeInterval { 15 }
}
