import Foundation

/// Formats rate-limit reset instants and "updated … ago" ages for display.
///
/// Rules (PLAN.md §5):
/// - in the past → `now`
/// - under a minute → `in <1m`
/// - under 24 h → `in 2h 15m` / `in 45m`
/// - otherwise weekday + local time (`Mon 14:00`, `Mon 2:00 PM`)
/// - more than 6 days away → date + time (`Sep 20, 14:00`)
public struct ResetFormatter {
    public var now: () -> Date
    public var calendar: Calendar
    public var locale: Locale
    public var timeZone: TimeZone

    public init(
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.timeZone = timeZone
    }

    /// Human string describing when `date` (a reset instant) occurs relative to `now`.
    public func string(for date: Date) -> String {
        let remaining = date.timeIntervalSince(now())
        if remaining <= 0 { return "now" }
        if remaining < 60 { return "in <1m" }
        if remaining < 24 * 3600 {
            let totalMinutes = Int(remaining / 60)
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return hours > 0 ? "in \(hours)h \(minutes)m" : "in \(minutes)m"
        }
        let template = remaining > 6 * 24 * 3600 ? "MMM d jm" : "EEE jm"
        return absoluteFormatter(template: template).string(from: date)
    }

    /// Short age string for "Updated … ago" footers: `just now`, `12 s ago`, `3 min ago`, `2 h ago`, `3 d ago`.
    public func relativeAge(since date: Date) -> String {
        let age = max(0, now().timeIntervalSince(date))
        if age < 1 { return "just now" }
        if age < 60 { return "\(Int(age)) s ago" }
        if age < 3600 { return "\(Int(age / 60)) min ago" }
        if age < 24 * 3600 { return "\(Int(age / 3600)) h ago" }
        return "\(Int(age / 86400)) d ago"
    }

    private func absoluteFormatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        var calendar = self.calendar
        calendar.locale = locale
        calendar.timeZone = timeZone
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
