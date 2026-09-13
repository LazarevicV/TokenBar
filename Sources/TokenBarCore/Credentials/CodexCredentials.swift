import Foundation

public struct CodexCredentials: Sendable {
    public let accessToken: String
    public let accountId: String
    public let authMode: String
    public let lastRefresh: Date?

    public init(accessToken: String, accountId: String, authMode: String, lastRefresh: Date? = nil) {
        self.accessToken = accessToken
        self.accountId = accountId
        self.authMode = authMode
        self.lastRefresh = lastRefresh
    }
}

public struct CodexCredentialSource: CredentialSource {
    public let path: URL

    public init(path: URL? = nil) {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        self.path = path ?? home.appendingPathComponent("auth.json")
    }

    public func load() throws -> CodexCredentials {
        let data: Data
        do {
            // Snapshot the whole file before parsing; the CLI can replace it at any time.
            data = try Data(contentsOf: path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw ProviderError.notLoggedIn("Codex is not signed in")
        } catch {
            throw ProviderError.decoding("Unable to read Codex credentials")
        }
        let auth: AuthFile
        do {
            auth = try JSONDecoder().decode(AuthFile.self, from: data)
        } catch {
            // Never include the JSON or decoder diagnostics: either can contain secrets.
            throw ProviderError.decoding("Invalid Codex credential file")
        }
        guard auth.auth_mode == "chatgpt",
              let token = auth.tokens?.access_token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let account = auth.tokens?.account_id, !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError.notLoggedIn("Codex is using an API key; sign in with ChatGPT to see limits")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let refresh = auth.last_refresh.flatMap { value -> Date? in
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }
        return CodexCredentials(accessToken: token, accountId: account, authMode: "chatgpt", lastRefresh: refresh)
    }

    private struct AuthFile: Decodable {
        var auth_mode: String?
        var tokens: Tokens?
        var last_refresh: String?

        struct Tokens: Decodable {
            var access_token: String?
            var account_id: String?
        }
    }
}
