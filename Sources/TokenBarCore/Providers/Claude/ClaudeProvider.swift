import Foundation

public struct ClaudeProvider: UsageProvider {
    public let id: ProviderID = .claude
    public let displayName = "Claude"

    private let loadCredentials: @Sendable () throws -> ClaudeCredentials
    private let send: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        credentialSource: ClaudeCredentialSource = ClaudeCredentialSource(),
        request: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) {
        self.loadCredentials = { try credentialSource.load() }
        self.send = request
    }

    public init<Source: CredentialSource>(
        credentialSource: Source,
        request: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) where Source.Credentials == ClaudeCredentials {
        self.loadCredentials = { try credentialSource.load() }
        self.send = request
    }

    public func fetch() async throws -> ProviderUsage {
        let credentials = try loadCredentials()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(TokenBarCore.userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(request)
        } catch let error as URLError {
            // Error userInfo may contain request details; describe only the code.
            throw ProviderError.network("Claude request failed (URL error \(error.code.rawValue))")
        }
        guard let response = response as? HTTPURLResponse else {
            throw ProviderError.network("Claude returned a non-HTTP response")
        }
        if response.statusCode == 401 || response.statusCode == 403 { throw ProviderError.tokenExpired }
        guard (200..<300).contains(response.statusCode) else { throw ProviderError.http(response.statusCode) }

        let usage: ClaudeUsageResponse
        do {
            usage = try ClaudeUsageResponse.decode(from: data)
        } catch {
            // Never surface body contents or decoder diagnostics from the API.
            throw ProviderError.decoding("Unable to decode Claude usage response")
        }
        var extras: [String] = []
        if usage.limits?.contains(where: {
            guard let severity = $0.severity else { return false }
            return !severity.isEmpty && severity.lowercased() != "normal"
        }) == true {
            extras.append("Limit reached")
        }
        if let extra = usage.extraUsage, extra.isEnabled == true {
            extras.append(Self.extraUsageLine(extra))
        }
        return ProviderUsage(
            provider: id,
            session: Self.window(usage.fiveHour, label: "5h"),
            weekly: Self.window(usage.sevenDay, label: "week"),
            plan: credentials.subscriptionType,
            extras: extras
        )
    }

    private static func window(_ window: ClaudeUsageResponse.Window?, label: String) -> UsageWindow? {
        guard let window, let resetsAt = window.resetsAt else { return nil }
        return UsageWindow(percent: window.utilization, resetsAt: resetsAt, label: label)
    }

    private static func extraUsageLine(_ extra: ClaudeUsageResponse.ExtraUsage) -> String {
        let decimalPlaces = min(max(extra.decimalPlaces ?? 2, 0), 6)
        let divisor = pow(10.0, Double(decimalPlaces))
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = extra.currency ?? "USD"
        formatter.minimumFractionDigits = decimalPlaces
        formatter.maximumFractionDigits = decimalPlaces
        func money(_ minorUnits: Double) -> String {
            formatter.string(from: NSNumber(value: minorUnits / divisor)) ?? "—"
        }
        if let utilization = extra.utilization {
            let percent = String(format: "%.0f%%", locale: Locale(identifier: "en_US_POSIX"), utilization * 100)
            if let limit = extra.monthlyLimit { return "Extra usage: \(percent) of \(money(limit))" }
            return "Extra usage: \(percent)"
        }
        if let used = extra.usedCredits {
            if let limit = extra.monthlyLimit { return "Extra usage: \(money(used)) of \(money(limit))" }
            return "Extra usage: \(money(used))"
        }
        return "Extra usage: enabled"
    }
}
