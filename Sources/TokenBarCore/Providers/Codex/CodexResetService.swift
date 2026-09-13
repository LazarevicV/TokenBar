import Foundation

/// One rate-limit reset credit as listed by the ChatGPT backend.
public struct ResetCredit: Equatable, Sendable {
    public var id: String
    public var title: String?
    public var status: String?
    public var expiresAt: Date?
    public var isSupportedByPlan: Bool

    public init(id: String, title: String? = nil, status: String? = nil, expiresAt: Date? = nil, isSupportedByPlan: Bool = true) {
        self.id = id
        self.title = title
        self.status = status
        self.expiresAt = expiresAt
        self.isSupportedByPlan = isSupportedByPlan
    }

    /// True when the backend reports the credit as redeemable on the current plan.
    public var isRedeemable: Bool { status == "available" && isSupportedByPlan }
}

/// Errors specific to redeeming reset credits; usage/transport errors are `ProviderError`.
public enum CodexResetError: Error, Equatable, Sendable, LocalizedError {
    case noCreditAvailable

    public var errorDescription: String? {
        switch self {
        case .noCreditAvailable: return "No reset credit is available to redeem."
        }
    }
}

/// Lists and redeems Codex rate-limit reset credits (unofficial ChatGPT backend endpoints).
///
/// Redeeming is irreversible: it spends one credit and resets both rate-limit windows.
public struct CodexResetService: Sendable {
    public typealias Transport = CodexProvider.Transport

    static let listURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    static let consumeURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume")!

    private let loadCredentials: @Sendable () throws -> CodexCredentials
    private let transport: Transport

    public init(
        credentialSource: CodexCredentialSource = CodexCredentialSource(),
        transport: @escaping Transport = { try await CodexProvider.defaultTransport($0) }
    ) {
        self.loadCredentials = { try credentialSource.load() }
        self.transport = transport
    }

    public init<Source: CredentialSource>(
        credentialSource: Source,
        transport: @escaping Transport = { try await CodexProvider.defaultTransport($0) }
    ) where Source.Credentials == CodexCredentials {
        self.loadCredentials = { try credentialSource.load() }
        self.transport = transport
    }

    public func listCredits() async throws -> [ResetCredit] {
        let data = try await send(url: Self.listURL, method: "GET", body: nil)
        let decoded: ListResponse
        do {
            decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        } catch {
            throw ProviderError.decoding("Invalid Codex reset-credit list response")
        }
        return (decoded.credits ?? []).compactMap { $0.credit }
    }

    /// Redeems the credit with the given id. Any 2xx response counts as success.
    public func redeem(creditId: String) async throws {
        let body = ConsumeRequest(redeem_request_id: UUID().uuidString, credit_id: creditId)
        let data = try JSONEncoder().encode(body)
        _ = try await send(url: Self.consumeURL, method: "POST", body: data)
    }

    /// Lists credits, redeems the first redeemable one and returns it.
    public func redeemFirstAvailable() async throws -> ResetCredit {
        guard let credit = try await listCredits().first(where: \.isRedeemable) else {
            throw CodexResetError.noCreditAvailable
        }
        try await redeem(creditId: credit.id)
        return credit
    }

    private func send(url: URL, method: String, body: Data?) async throws -> Data {
        try Task.checkCancellation()
        let credentials = try loadCredentials()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue(TokenBarCore.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            // No transport retry: a POST that timed out may already have been applied.
            throw ProviderError.network("Codex request failed (URL error \(error.code.rawValue))")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.network("Codex returned a non-HTTP response")
        }
        switch http.statusCode {
        case 401, 403: throw ProviderError.tokenExpired
        case 200..<300: return data
        default: throw ProviderError.http(http.statusCode)
        }
    }

    private struct ConsumeRequest: Encodable {
        var redeem_request_id: String
        var credit_id: String
    }

    struct ListResponse: Decodable {
        var credits: [Entry]?
        var available_count: Int?

        struct Entry: Decodable {
            var id: String?
            var title: String?
            var status: String?
            var expires_at: String?
            var is_supported_by_plan: Bool?

            var credit: ResetCredit? {
                guard let id, !id.isEmpty else { return nil }
                return ResetCredit(
                    id: id,
                    title: title,
                    status: status,
                    expiresAt: expires_at.flatMap(Self.parseDate),
                    isSupportedByPlan: is_supported_by_plan ?? true
                )
            }

            static func parseDate(_ value: String) -> Date? {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: value) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: value)
            }
        }
    }
}
