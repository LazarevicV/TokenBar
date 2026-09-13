import Foundation
import Testing
@testable import TokenBarCore

private let testClaudeSource = ClaudeCredentialSource(keychainReader: { _ in claudeCredentialFixture })

private func response(_ request: URLRequest, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

@Test func claudeProviderMapsUsageAndSendsRequiredHeaders() async throws {
    let provider = ClaudeProvider(credentialSource: testClaudeSource) { request in
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.timeoutInterval == 10)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer redacted-test-token")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == TokenBarCore.userAgent)
        return (claudeUsageFixture, response(request, status: 200))
    }
    #expect(provider.id == .claude)
    #expect(provider.displayName == "Claude")
    let usage = try await provider.fetch()
    #expect(usage.provider == .claude)
    #expect(usage.session?.percent == 5.5)
    #expect(usage.session?.label == "5h")
    #expect(usage.weekly?.percent == 12)
    #expect(usage.weekly?.label == "week")
    let session = try #require(usage.session)
    let weekly = try #require(usage.weekly)
    #expect(abs(session.resetsAt.timeIntervalSince1970 - 1789315800.944794) < 0.001)
    #expect(abs(weekly.resetsAt.timeIntervalSince1970 - 1789761600.944817) < 0.001)
    #expect(usage.plan == "pro")
    #expect(usage.extras == ["Extra usage: 21% of $99.00"])
}

@Test(arguments: [401, 403, 429, 500]) func claudeProviderMapsHTTPFailures(status: Int) async {
    let provider = ClaudeProvider(credentialSource: testClaudeSource) { request in
        (Data("redacted response".utf8), response(request, status: status))
    }
    await #expect(throws: status == 401 || status == 403 ? ProviderError.tokenExpired : ProviderError.http(status)) {
        try await provider.fetch()
    }
}

@Test(arguments: ["not JSON redacted-secret", #"{"five_hour":{"utilization":"redacted-secret"}}"#, #"{"five_hour":{"utilization":0,"resets_at":"redacted-secret"}}"#])
func claudeProviderRedactsDecodeFailures(body: String) async {
    let provider = ClaudeProvider(credentialSource: testClaudeSource) { request in
        (Data(body.utf8), response(request, status: 200))
    }
    await #expect(throws: ProviderError.decoding("Unable to decode Claude usage response")) {
        try await provider.fetch()
    }
}

@Test func claudeProviderMapsNetworkFailureWithoutSensitiveUserInfo() async {
    let provider = ClaudeProvider(credentialSource: testClaudeSource) { _ in
        throw URLError(.notConnectedToInternet, userInfo: [NSLocalizedDescriptionKey: "redacted-secret"])
    }
    await #expect(throws: ProviderError.network("Claude request failed (URL error -1009)")) {
        try await provider.fetch()
    }
}

@Test func claudeProviderNullWindowsAndSeverity() async throws {
    let provider = ClaudeProvider(credentialSource: testClaudeSource) { request in
        (Data(#"{"five_hour":null,"seven_day":null,"limits":[{"severity":"warning"},{"severity":"critical"}],"extra_usage":{"is_enabled":false,"utilization":0.5}}"#.utf8), response(request, status: 200))
    }
    let usage = try await provider.fetch()
    #expect(usage.session == nil)
    #expect(usage.weekly == nil)
    #expect(usage.extras == ["Limit reached"])
}

@Test func claudeProviderFormatsMinorUnitsWhenUtilizationMissing() async throws {
    let provider = ClaudeProvider(credentialSource: testClaudeSource) { request in
        (Data(#"{"extra_usage":{"is_enabled":true,"used_credits":21.0,"monthly_limit":9900,"currency":"USD","decimal_places":2}}"#.utf8), response(request, status: 200))
    }
    #expect(try await provider.fetch().extras == ["Extra usage: $0.21 of $99.00"])
}

@Test func claudeProviderLoadsFreshCredentialsEveryFetch() async throws {
    final class RotatingSource: CredentialSource, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func load() throws -> ClaudeCredentials {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return ClaudeCredentials(accessToken: "redacted-\(count)", expiresAt: .distantFuture, subscriptionType: "plan-\(count)")
        }
    }
    let provider = ClaudeProvider(credentialSource: RotatingSource()) { request in
        #expect(["Bearer redacted-1", "Bearer redacted-2"].contains(request.value(forHTTPHeaderField: "Authorization") ?? ""))
        return (Data("{}".utf8), response(request, status: 200))
    }
    #expect(try await provider.fetch().plan == "plan-1")
    #expect(try await provider.fetch().plan == "plan-2")
}

@Test func claudeProviderDoesNotRequestWithoutCredentials() async {
    let source = ClaudeCredentialSource(keychainReader: { _ in throw ProviderError.notLoggedIn("Run claude to sign in") })
    let provider = ClaudeProvider(credentialSource: source) { request in
        Issue.record("Must not send a request without credentials")
        return (Data(), response(request, status: 200))
    }
    await #expect(throws: ProviderError.notLoggedIn("Run claude to sign in")) { try await provider.fetch() }
}
