import Foundation

/// Severity bucket for a remaining percentage; drives bar / menu-bar colour.
public enum UsageLevel: Equatable, Sendable {
    case normal
    case warning
    case critical

    /// `> 30` left → normal, `10–30` left → warning, `< 10` left → critical. NaN is treated as normal.
    public init(remaining: Double) {
        if remaining < 10 {
            self = .critical
        } else if remaining <= 30 {
            self = .warning
        } else {
            self = .normal
        }
    }
}

/// Number of filled segments in a `total`-segment bar for a remaining percentage:
/// `round(remaining / (100 / total))`, clamped to `0...total`. A full bar means plenty left.
public func filledSegments(remaining: Double, total: Int = 10) -> Int {
    guard total > 0, remaining.isFinite else { return 0 }
    let raw = (remaining / (100.0 / Double(total))).rounded()
    return min(max(Int(raw), 0), total)
}
