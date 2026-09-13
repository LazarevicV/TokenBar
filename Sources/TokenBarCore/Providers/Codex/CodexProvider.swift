import Foundation

public struct CodexProvider: UsageProvider {
    public let id: ProviderID = .codex
    public let displayName = "Codex"
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

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

    public static func defaultTransport(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }

    public func fetch() async throws -> ProviderUsage {
        var retriedUnauthorized = false
        var retriedTransport = false
        while true {
            try Task.checkCancellation()
            let credentials = try loadCredentials()
            var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(credentials.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
            request.setValue(TokenBarCore.userAgent, forHTTPHeaderField: "User-Agent")
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await transport(request)
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                if !retriedTransport {
                    retriedTransport = true
                    continue
                }
                throw ProviderError.network("Codex request failed (URL error \(error.code.rawValue))")
            }
            guard let response = response as? HTTPURLResponse else {
                throw ProviderError.network("Codex returned a non-HTTP response")
            }
            if response.statusCode == 401 && !retriedUnauthorized {
                retriedUnauthorized = true
                continue
            }
            switch response.statusCode {
            case 401, 403: throw ProviderError.tokenExpired
            case 200..<300: break
            default: throw ProviderError.http(response.statusCode)
            }
            let decoded: CodexUsageResponse
            do {
                decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            } catch {
                throw ProviderError.decoding("Invalid Codex usage response")
            }
            let limited = decoded.rate_limit?.limit_reached == true || decoded.rate_limit?.allowed == false
            return ProviderUsage(
                provider: .codex,
                session: decoded.rate_limit?.primary_window?.usageWindow,
                weekly: decoded.rate_limit?.secondary_window?.usageWindow,
                plan: decoded.plan_type,
                extras: limited ? ["Limit reached"] : []
            )
        }
    }
}

/// Do not forward account headers or bearer credentials to a redirect destination.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
