import Foundation
import Testing
@testable import TokenBarCore

private struct TestCredentials: CredentialSource {
    func load() throws -> CodexCredentials {
        CodexCredentials(accessToken: "redacted-token", accountId: "redacted-account", authMode: "chatgpt")
    }
}

private func response(_ request: URLRequest, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

/// Captured from the live endpoint on 2026-09-13; ids redacted.
let codexResetCreditsFixture = #"{"credits":[{"id":"RateLimitResetCredit_redacted1","reset_type":"codex_rate_limits","is_supported_by_plan":true,"status":"available","granted_at":"2026-09-01T10:00:00Z","expires_at":"2026-12-01T10:00:00.123456Z","redeemed_at":null,"title":"Full reset (Weekly + 5 hr)","description":"Resets your weekly and 5-hour limits."},{"id":"RateLimitResetCredit_redacted2","reset_type":"codex_rate_limits","is_supported_by_plan":true,"status":"available","granted_at":"2026-09-01T10:00:00Z","expires_at":"2026-12-01T10:00:00Z","redeemed_at":null,"title":"Full reset (Weekly + 5 hr)","description":"…"}],"available_count":2,"total_earned_count":0,"immediate_reset_purchase_eligible":false,"history_enabled":true}"#

@Test func resetServiceListsCredits() async throws {
    let service = CodexResetService(credentialSource: TestCredentials()) { request in
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer redacted-token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "redacted-account")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == TokenBarCore.userAgent)
        return (Data(codexResetCreditsFixture.utf8), response(request, status: 200))
    }
    let credits = try await service.listCredits()
    #expect(credits.count == 2)
    #expect(credits[0].id == "RateLimitResetCredit_redacted1")
    #expect(credits[0].title == "Full reset (Weekly + 5 hr)")
    #expect(credits[0].status == "available")
    #expect(credits[0].isSupportedByPlan)
    #expect(credits[0].isRedeemable)
    #expect(credits[0].expiresAt != nil)
    #expect(credits[1].expiresAt == ISO8601DateFormatter().date(from: "2026-12-01T10:00:00Z"))
}

@Test(arguments: ["{}", #"{"credits":null}"#, #"{"credits":[{"title":"no id"}]}"#])
func resetServiceListsNothingLeniently(json: String) async throws {
    let service = CodexResetService(credentialSource: TestCredentials()) { request in
        (Data(json.utf8), response(request, status: 200))
    }
    #expect(try await service.listCredits().isEmpty)
}

@Test func resetServiceRedeemSendsPost() async throws {
    let service = CodexResetService(credentialSource: TestCredentials()) { request in
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer redacted-token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "redacted-account")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == TokenBarCore.userAgent)
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(body?["credit_id"] as? String == "RateLimitResetCredit_redacted1")
        let requestId = body?["redeem_request_id"] as? String
        #expect(requestId.flatMap(UUID.init(uuidString:)) != nil)
        #expect(body?.count == 2)
        return (Data(#"{"windows_reset":["primary","secondary"]}"#.utf8), response(request, status: 200))
    }
    try await service.redeem(creditId: "RateLimitResetCredit_redacted1")
}

@Test func resetServiceRedeemToleratesOpaqueResponse() async throws {
    let service = CodexResetService(credentialSource: TestCredentials()) { request in
        (Data("not json".utf8), response(request, status: 204))
    }
    try await service.redeem(creditId: "RateLimitResetCredit_redacted1")
}

@Test(arguments: [401, 403, 409, 429, 500])
func resetServiceHTTPFailures(status: Int) async {
    let service = CodexResetService(credentialSource: TestCredentials()) { request in
        (Data(), response(request, status: status))
    }
    let expected = status == 401 || status == 403 ? ProviderError.tokenExpired : ProviderError.http(status)
    await #expect(throws: expected) { try await service.redeem(creditId: "x") }
    await #expect(throws: expected) { try await service.listCredits() }
}

private actor RequestLog {
    var urls: [URL] = []
    var creditIds: [String] = []
    func record(_ request: URLRequest) {
        urls.append(request.url!)
        if let body = request.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let id = json["credit_id"] as? String {
            creditIds.append(id)
        }
    }
}

@Test func redeemFirstAvailableSkipsNonRedeemableCredits() async throws {
    let list = #"{"credits":[{"id":"redeemed","status":"redeemed","is_supported_by_plan":true},{"id":"unsupported","status":"available","is_supported_by_plan":false},{"id":"good","status":"available","is_supported_by_plan":true,"title":"Full reset"},{"id":"also-good","status":"available","is_supported_by_plan":true}]}"#
    let log = RequestLog()
    let service = CodexResetService(credentialSource: TestCredentials()) { request in
        await log.record(request)
        if request.httpMethod == "GET" {
            return (Data(list.utf8), response(request, status: 200))
        }
        return (Data("{}".utf8), response(request, status: 200))
    }
    let credit = try await service.redeemFirstAvailable()
    #expect(credit.id == "good")
    #expect(credit.title == "Full reset")
    #expect(await log.creditIds == ["good"])
    #expect(await log.urls == [CodexResetService.listURL, CodexResetService.consumeURL])
}

@Test func redeemFirstAvailableThrowsWhenNoneRedeemable() async throws {
    let list = #"{"credits":[{"id":"redeemed","status":"redeemed","is_supported_by_plan":true}],"available_count":0}"#
    let log = RequestLog()
    let service = CodexResetService(credentialSource: TestCredentials()) { request in
        await log.record(request)
        return (Data(list.utf8), response(request, status: 200))
    }
    await #expect(throws: CodexResetError.noCreditAvailable) { try await service.redeemFirstAvailable() }
    // Never POSTs when nothing is redeemable.
    #expect(await log.urls == [CodexResetService.listURL])
}

@Test func resetServiceNetworkErrorIsRedactedAndNotRetried() async {
    let log = RequestLog()
    let service = CodexResetService(credentialSource: TestCredentials()) { request in
        await log.record(request)
        throw URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "redacted-secret"])
    }
    await #expect(throws: ProviderError.network("Codex request failed (URL error -1001)")) {
        try await service.redeem(creditId: "x")
    }
    #expect(await log.urls.count == 1)
}

/// Live check of the read-only list endpoint. Never redeems.
@Test(.enabled(if: ProcessInfo.processInfo.environment["TOKENBAR_LIVE"] == "1"))
func codexLiveResetCreditList() async throws {
    let credits = try await CodexResetService().listCredits()
    let usage = try await CodexProvider().fetch()
    // Only counts are printed; no ids, titles or account data.
    print("TOKENBAR_LIVE reset credits: listed=\(credits.count) redeemable=\(credits.filter(\.isRedeemable).count) usage.available=\(usage.resetCreditsAvailable.map(String.init) ?? "nil")")
    fflush(stdout)
    #expect(usage.resetCreditsAvailable != nil)
}
