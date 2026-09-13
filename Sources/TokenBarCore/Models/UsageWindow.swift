import Foundation

/// One rate-limit window (e.g. the 5-hour session window or the 7-day weekly window).
public struct UsageWindow: Equatable, Sendable {
    /// Utilisation in percent, 0–100.
    public var percent: Double
    /// When the window resets (UTC instant; format in local time zone for display).
    /// `nil` when the window is idle: Claude omits the 5-hour reset until a session starts.
    public var resetsAt: Date?
    /// Human label such as "5h" or "week".
    public var label: String

    /// Percentage still available in this window: `100 - percent`, clamped to 0–100. NaN yields 0.
    public var remaining: Double {
        guard !percent.isNaN else { return 0 }
        return max(0, min(100, 100 - percent))
    }

    public init(percent: Double, resetsAt: Date?, label: String) {
        self.percent = percent
        self.resetsAt = resetsAt
        self.label = label
    }
}
