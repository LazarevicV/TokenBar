import Foundation
import Testing
@testable import TokenBarCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["TOKENBAR_LIVE"] == "1"))
func claudeLiveUsage() async throws {
    // Keep failures token-free, including credential and transport errors.
    let usage: ProviderUsage
    do {
        usage = try await ClaudeProvider().fetch()
    } catch {
        Issue.record("Live Claude request failed; check CLI sign-in and connectivity")
        return
    }
    #expect(usage.session != nil)
    #expect(usage.weekly != nil)
}
