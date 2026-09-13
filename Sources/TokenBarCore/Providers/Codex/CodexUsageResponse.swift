import Foundation

/// Unknown fields are ignored; absent/null limits are normal on some plans.
public struct CodexUsageResponse: Codable, Sendable {
    public var plan_type: String?
    public var rate_limit: RateLimit?
    public var credits: Credits?
    public var rate_limit_reset_credits: ResetCredits?

    public struct RateLimit: Codable, Sendable {
        public var allowed: Bool?
        public var limit_reached: Bool?
        public var primary_window: Window?
        public var secondary_window: Window?
    }

    public struct Window: Codable, Sendable {
        public var used_percent: Double?
        public var limit_window_seconds: Int?
        public var reset_after_seconds: Int?
        public var reset_at: Int?

        var usageWindow: UsageWindow? {
            guard let percent = used_percent, let seconds = limit_window_seconds,
                  let reset = reset_at else { return nil }
            return UsageWindow(percent: percent, resetsAt: Date(timeIntervalSince1970: Double(reset)),
                               label: Self.label(seconds: seconds))
        }

        static func label(seconds: Int) -> String {
            if seconds == 604800 { return "week" }
            if seconds > 0 && seconds % 86400 == 0 { return "\(seconds / 86400)d" }
            if seconds > 0 && seconds % 3600 == 0 { return "\(seconds / 3600)h" }
            if seconds > 0 && seconds % 60 == 0 { return "\(seconds / 60)m" }
            return "\(seconds)s"
        }
    }

    public struct Credits: Codable, Sendable {
        public var has_credits: Bool?
        public var balance: String?
    }

    public struct ResetCredits: Codable, Sendable {
        public var available_count: Int?
        public var applicable_available_count: Int?
    }
}
