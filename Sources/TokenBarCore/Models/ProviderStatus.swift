import Foundation

/// The state of one provider as shown in the popover.
public enum ProviderStatus: Equatable, Sendable {
    case loading
    case ok(ProviderUsage)
    case notLoggedIn
    case tokenExpired
    case error(String)
}
