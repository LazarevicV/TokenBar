import Foundation

/// Stable identifier for a usage provider.
public struct ProviderID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let claude: ProviderID = "claude"
    public static let codex: ProviderID = "codex"
}

/// A snapshot of one provider's usage as returned by its account-side usage API.
public struct ProviderUsage: Equatable, Sendable {
    public var provider: ProviderID
    public var session: UsageWindow?
    public var weekly: UsageWindow?
    /// Plan / subscription name, e.g. "pro", "plus".
    public var plan: String?
    /// Free-form secondary lines (e.g. extra-usage credits).
    public var extras: [String]
    /// Number of rate-limit reset credits the account can redeem (Codex only); nil when the provider does not report it.
    public var resetCreditsAvailable: Int?

    public init(
        provider: ProviderID,
        session: UsageWindow? = nil,
        weekly: UsageWindow? = nil,
        plan: String? = nil,
        extras: [String] = [],
        resetCreditsAvailable: Int? = nil
    ) {
        self.provider = provider
        self.session = session
        self.weekly = weekly
        self.plan = plan
        self.extras = extras
        self.resetCreditsAvailable = resetCreditsAvailable
    }
}
