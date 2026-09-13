import Foundation
import TokenBarCore

/// One provider row-group in the popover: identity, display name and its current status.
public struct ProviderSection: Identifiable, Equatable {
    public var id: ProviderID
    public var displayName: String
    public var status: ProviderStatus

    public init(id: ProviderID, displayName: String, status: ProviderStatus) {
        self.id = id
        self.displayName = displayName
        self.status = status
    }
}
