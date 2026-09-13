import Foundation
import TokenBarCore

/// One provider row-group in the popover: identity, display name and its current status.
public struct ProviderSection: Identifiable, Equatable {
    public var id: ProviderID
    public var displayName: String
    public var status: ProviderStatus
    /// When set, `status` carries last-good data and this explains why it is stale (shown with a Retry button).
    public var staleMessage: String?

    public init(id: ProviderID, displayName: String, status: ProviderStatus, staleMessage: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.status = status
        self.staleMessage = staleMessage
    }
}
