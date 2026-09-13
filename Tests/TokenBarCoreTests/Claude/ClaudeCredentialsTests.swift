import Foundation
import Testing
@testable import TokenBarCore

let claudeCredentialFixture = Data(#"""
{"claudeAiOauth":{"accessToken":"redacted-test-token","expiresAt":1789329289644,"subscriptionType":"pro","rateLimitTier":"default_claude_ai","refreshToken":"redacted","unknown":true},"unknown":{}}
"""#.utf8)

@Test func claudeCredentialsDecodeMillisecondsAndIgnoreUnknownKeys() throws {
    let credentials = try ClaudeCredentials.decode(from: claudeCredentialFixture)
    #expect(credentials.accessToken == "redacted-test-token")
    #expect(abs(credentials.expiresAt.timeIntervalSince1970 - 1789329289.644) < 0.001)
    #expect(credentials.subscriptionType == "pro")
    #expect(credentials.rateLimitTier == "default_claude_ai")
}

@Test func claudeCredentialsPreferKeychain() throws {
    let source = ClaudeCredentialSource(keychainReader: { service in
        #expect(service == "Claude Code-credentials")
        return claudeCredentialFixture
    }, filePath: URL(fileURLWithPath: "/nonexistent/credentials.json"))
    #expect(try source.load().accessToken == "redacted-test-token")
}

@Test func claudeCredentialsFileFallbackAndConfigDirectory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent(".credentials.json")
    try claudeCredentialFixture.write(to: file)
    let explicit = ClaudeCredentialSource(keychainReader: { _ in nil }, filePath: file)
    #expect(try explicit.load().subscriptionType == "pro")
    let configured = ClaudeCredentialSource(keychainReader: { _ in nil }, environment: ["CLAUDE_CONFIG_DIR": directory.path])
    #expect(try configured.load().accessToken == "redacted-test-token")
}

@Test func claudeMissingCredentialsAreNotLoggedIn() {
    let source = ClaudeCredentialSource(keychainReader: { _ in nil }, filePath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    #expect(throws: ProviderError.notLoggedIn("Run claude to sign in")) { try source.load() }
}

@Test func claudeCredentialErrorsDoNotExposeJSON() {
    #expect(throws: CredentialError.malformed("Unable to decode Claude credentials")) {
        try ClaudeCredentials.decode(from: Data(#"{"claudeAiOauth":{"accessToken":"redacted-secret","expiresAt":"redacted-secret"}}"#.utf8))
    }
}

@Test func claudeKeychainFailureIsNotSilentlyIgnored() {
    let source = ClaudeCredentialSource(keychainReader: { _ in throw CredentialError.notFound })
    #expect(throws: CredentialError.notFound) { try source.load() }
}

@Test func claudeOptionalCredentialMetadata() throws {
    let credentials = try ClaudeCredentials.decode(from: Data(#"{"claudeAiOauth":{"accessToken":"redacted","expiresAt":1000}}"#.utf8))
    #expect(credentials.subscriptionType == nil)
    #expect(credentials.rateLimitTier == nil)
}
