import Foundation
import Testing
@testable import TokenBarCore

private struct TestCodexCredentials: CredentialSource {
    func load() throws -> CodexCredentials {
        CodexCredentials(accessToken: "redacted-token", accountId: "redacted-account", authMode: "chatgpt")
    }
}

private func httpResponse(_ request: URLRequest, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

@Test func codexProviderSuccess() async throws {
    let provider = CodexProvider(credentialSource: TestCodexCredentials()) { request in
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.timeoutInterval == 10)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer redacted-token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "redacted-account")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == TokenBarCore.userAgent)
        return (Data(codexUsageFixture.utf8), httpResponse(request, status: 200))
    }
    #expect(provider.id == .codex)
    #expect(provider.displayName == "Codex")
    let usage = try await provider.fetch()
    #expect(usage.provider == .codex)
    #expect(usage.plan == "plus")
    #expect(usage.session == UsageWindow(percent: 54, resetsAt: Date(timeIntervalSince1970: 1789313353), label: "5h"))
    #expect(usage.weekly == UsageWindow(percent: 8.5, resetsAt: Date(timeIntervalSince1970: 1789811371), label: "week"))
    #expect(usage.extras.isEmpty)
}

@Test(arguments: [401, 403, 429, 500])
func codexHTTPFailures(status: Int) async {
    let provider = CodexProvider(credentialSource: TestCodexCredentials()) { request in
        (Data(), httpResponse(request, status: status))
    }
    await #expect(throws: status == 401 || status == 403 ? ProviderError.tokenExpired : ProviderError.http(status)) {
        try await provider.fetch()
    }
}

@Test(arguments: [#"{"allowed":false}"#, #"{"limit_reached":true}"#, #"{"allowed":false,"limit_reached":true}"#])
func codexLimitReached(flags: String) async throws {
    let provider = CodexProvider(credentialSource: TestCodexCredentials()) { request in
        (Data("{\"rate_limit\":\(flags)}".utf8), httpResponse(request, status: 200))
    }
    let usage = try await provider.fetch()
    #expect(usage.session == nil)
    #expect(usage.weekly == nil)
    #expect(usage.extras == ["Limit reached"])
}

@Test func codexDecodeFailureIsRedacted() async {
    let provider = CodexProvider(credentialSource: TestCodexCredentials()) { request in
        (Data(#"{"rate_limit":"redacted-sensitive-value"}"#.utf8), httpResponse(request, status: 200))
    }
    await #expect(throws: ProviderError.decoding("Invalid Codex usage response")) { try await provider.fetch() }
}

private actor RequestCounter {
    var count = 0
    func next() -> Int { count += 1; return count }
}

@Test func codexTransportRetryIsBoundedAndRedacted() async {
    let counter = RequestCounter()
    let provider = CodexProvider(credentialSource: TestCodexCredentials()) { _ in
        _ = await counter.next()
        throw URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "redacted-secret"])
    }
    await #expect(throws: ProviderError.network("Codex request failed (URL error -1001)")) { try await provider.fetch() }
    #expect(await counter.count == 2)
}

@Test func codexTransportRetryRecovers() async throws {
    let counter = RequestCounter()
    let provider = CodexProvider(credentialSource: TestCodexCredentials()) { request in
        if await counter.next() == 1 { throw URLError(.networkConnectionLost) }
        return (Data(codexUsageFixture.utf8), httpResponse(request, status: 200))
    }
    #expect(try await provider.fetch().session != nil)
    #expect(await counter.count == 2)
}

@Test func codexReadsFreshCredentialsAfterUnauthorizedAndOnEachFetch() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("auth.json")
    let initial = #"{"auth_mode":"chatgpt","tokens":{"access_token":"redacted-old","account_id":"redacted-account"}}"#
    let updated = #"{"auth_mode":"chatgpt","tokens":{"access_token":"redacted-new","account_id":"redacted-account"}}"#
    try Data(initial.utf8).write(to: path)
    let counter = RequestCounter()
    let provider = CodexProvider(credentialSource: CodexCredentialSource(path: path)) { request in
        if await counter.next() == 1 {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer redacted-old")
            try Data(updated.utf8).write(to: path)
            return (Data(), httpResponse(request, status: 401))
        }
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer redacted-new")
        return (Data(codexUsageFixture.utf8), httpResponse(request, status: 200))
    }
    #expect(try await provider.fetch().session != nil)
    #expect(try await provider.fetch().weekly != nil)
    #expect(await counter.count == 3)
}

@Test func codexCancellationDoesNotRetry() async {
    let counter = RequestCounter()
    let provider = CodexProvider(credentialSource: TestCodexCredentials()) { _ in
        _ = await counter.next()
        throw URLError(.cancelled)
    }
    await #expect(throws: CancellationError.self) { try await provider.fetch() }
    #expect(await counter.count == 1)
}
