import Foundation
import Testing
@testable import TokenBarCore

private func withAuth(_ json: String, body: (CodexCredentialSource) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("auth.json")
    try Data(json.utf8).write(to: path)
    try body(CodexCredentialSource(path: path))
}

@Test func codexCredentialsParse() throws {
    try withAuth(#"{"auth_mode":"chatgpt","tokens":{"access_token":"redacted-token","account_id":"redacted-account","id_token":"not-a-jwt","unknown":true},"last_refresh":"2026-09-09T08:15:56.367178Z","unknown":42}"#) { source in
        let credentials = try source.load()
        #expect(credentials.accessToken == "redacted-token")
        #expect(credentials.accountId == "redacted-account")
        #expect(credentials.authMode == "chatgpt")
        #expect(credentials.lastRefresh != nil)
    }
}

@Test(arguments: [#"{"auth_mode":"apikey"}"#, #"{"auth_mode":"chatgpt","tokens":null}"#, #"{"auth_mode":"chatgpt","tokens":{"access_token":"","account_id":"redacted"}}"#, "{}"])
func codexCredentialsRequireChatGPT(json: String) throws {
    try withAuth(json) { source in
        #expect(throws: ProviderError.notLoggedIn("Codex is using an API key; sign in with ChatGPT to see limits")) {
            try source.load()
        }
    }
}

@Test func codexCredentialsMissingFile() {
    let source = CodexCredentialSource(path: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    #expect(throws: ProviderError.notLoggedIn("Codex is not signed in")) { try source.load() }
}

@Test(arguments: ["2026-09-09T08:15:56Z", "invalid"])
func codexRefreshDateIsOptional(value: String) throws {
    try withAuth("{\"auth_mode\":\"chatgpt\",\"tokens\":{\"access_token\":\"redacted\",\"account_id\":\"redacted\"},\"last_refresh\":\"\(value)\"}") { source in
        let refresh = try source.load().lastRefresh
        #expect((refresh != nil) == (value != "invalid"))
    }
}

@Test func codexMalformedCredentialsAreRedacted() throws {
    try withAuth("{redacted-secret") { source in
        #expect(throws: ProviderError.decoding("Invalid Codex credential file")) { try source.load() }
    }
}
