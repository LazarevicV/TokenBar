import Foundation

/// Errors a `UsageProvider` can throw. `UsageStore` maps these onto `ProviderStatus`.
public enum ProviderError: Error, Equatable, Sendable {
    /// No credentials found (CLI never logged in, or wrong auth mode).
    case notLoggedIn(String)
    /// Credentials exist but the API rejected them (HTTP 401/403).
    case tokenExpired
    /// Transport-level failure (offline, timeout).
    case network(String)
    /// Unexpected HTTP status; includes 429 and 5xx (callers may back off).
    case http(Int)
    /// Response could not be decoded; message must be redacted (no tokens/emails).
    case decoding(String)
}
