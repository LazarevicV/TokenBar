import Foundation

public struct ClaudeCredentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date
    public let subscriptionType: String?
    public let rateLimitTier: String?

    public init(accessToken: String, expiresAt: Date, subscriptionType: String? = nil, rateLimitTier: String? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    /// Decode the CLI's JSON without retaining refresh tokens or unknown fields.
    public static func decode(from data: Data) throws -> ClaudeCredentials {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Double
            let subscriptionType: String?
            let rateLimitTier: String?
        }
        struct Envelope: Decodable { let claudeAiOauth: OAuth }
        do {
            let oauth = try JSONDecoder().decode(Envelope.self, from: data).claudeAiOauth
            guard !oauth.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CredentialError.malformed("Missing Claude access token")
            }
            return ClaudeCredentials(
                accessToken: oauth.accessToken,
                expiresAt: Date(timeIntervalSince1970: oauth.expiresAt / 1_000),
                subscriptionType: oauth.subscriptionType,
                rateLimitTier: oauth.rateLimitTier
            )
        } catch {
            throw CredentialError.malformed("Unable to decode Claude credentials")
        }
    }
}

public struct ClaudeCredentialSource: CredentialSource {
    private let keychainReader: @Sendable (String) throws -> Data?
    private let filePath: URL

    public init(
        keychainReader: @escaping @Sendable (String) throws -> Data? = { try KeychainReader.read(service: $0) },
        filePath: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.keychainReader = keychainReader
        let directory = environment["CLAUDE_CONFIG_DIR"].map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        self.filePath = filePath ?? directory.appendingPathComponent(".credentials.json")
    }

    public func load() throws -> ClaudeCredentials {
        if let data = try keychainReader("Claude Code-credentials") {
            return try ClaudeCredentials.decode(from: data)
        }
        do {
            return try ClaudeCredentials.decode(from: Data(contentsOf: filePath))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            throw ProviderError.notLoggedIn("Run claude to sign in")
        }
    }
}
