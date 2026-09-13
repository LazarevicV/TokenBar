import Testing
@testable import TokenBarCore

@Test func providerUsageDefaults() {
    let usage = ProviderUsage(provider: .claude)
    #expect(usage.provider == .claude)
    #expect(usage.session == nil)
    #expect(usage.weekly == nil)
    #expect(usage.extras.isEmpty)
    #expect(TokenBarCore.userAgent == "TokenBar/0.1.0")
}
