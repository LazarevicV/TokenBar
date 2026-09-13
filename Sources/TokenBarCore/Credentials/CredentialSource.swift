import Foundation

/// Where a provider's credentials come from (CLI keychain item, auth.json, …).
/// Kept as a protocol so an app-owned login can be added later without touching providers.
public protocol CredentialSource: Sendable {
    associatedtype Credentials: Sendable
    func load() throws -> Credentials
}

/// Errors common to all credential sources.
public enum CredentialError: Error, Equatable, Sendable {
    case notFound
    case malformed(String)
}
