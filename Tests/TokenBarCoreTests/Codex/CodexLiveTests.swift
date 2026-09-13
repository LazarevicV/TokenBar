import Foundation
import Testing
@testable import TokenBarCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["TOKENBAR_LIVE"] == "1"))
func codexLiveUsage() async throws {
    // Do not print credentials, account metadata, or the response body.
    let usage = try await CodexProvider().fetch()
    #expect(usage.session != nil)
    #expect(usage.weekly != nil)
}
