import Foundation

/// A source of rate-limit usage for one account (Claude, Codex, …).
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    /// Reads credentials fresh and fetches the current usage snapshot.
    func fetch() async throws -> ProviderUsage
}
