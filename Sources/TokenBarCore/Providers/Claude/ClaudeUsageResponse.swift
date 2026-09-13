import Foundation

/// Only the usage fields understood by TokenBar; new server fields are ignored.
public struct ClaudeUsageResponse: Codable, Sendable {
    public struct Window: Codable, Sendable {
        public let utilization: Double
        public let resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    public struct Limit: Codable, Sendable {
        public let kind: String?
        public let group: String?
        public let percent: Double?
        public let severity: String?
        public let resetsAt: Date?
        public let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case kind, group, percent, severity
            case resetsAt = "resets_at"
            case isActive = "is_active"
        }
    }

    public struct ExtraUsage: Codable, Sendable {
        public let isEnabled: Bool?
        /// Fraction (0–1), unlike a window's utilization (0–100).
        public let utilization: Double?
        /// Monetary values are minor units, with two decimal places by default.
        public let usedCredits: Double?
        public let monthlyLimit: Double?
        public let currency: String?
        public let decimalPlaces: Int?

        enum CodingKeys: String, CodingKey {
            case utilization, currency
            case isEnabled = "is_enabled"
            case usedCredits = "used_credits"
            case monthlyLimit = "monthly_limit"
            case decimalPlaces = "decimal_places"
        }
    }

    public let fiveHour: Window?
    public let sevenDay: Window?
    public let sevenDayOpus: Window?
    public let sevenDaySonnet: Window?
    public let limits: [Limit]?
    public let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case limits
        case extraUsage = "extra_usage"
    }

    public static func decode(from data: Data) throws -> ClaudeUsageResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Claude reset date")
        }
        return try decoder.decode(Self.self, from: data)
    }
}
