import Foundation

/// Severity bucket for a usage percentage; drives bar / menu-bar colour.
public enum UsageLevel: Equatable, Sendable {
    case normal
    case warning
    case critical

    /// `< 70` → normal, `70–89` → warning, `>= 90` → critical. NaN is treated as normal.
    public init(percent: Double) {
        if percent >= 90 {
            self = .critical
        } else if percent >= 70 {
            self = .warning
        } else {
            self = .normal
        }
    }
}

/// Number of filled segments in a `total`-segment bar: `round(percent / (100 / total))`, clamped to `0...total`.
public func filledSegments(percent: Double, total: Int = 10) -> Int {
    guard total > 0, percent.isFinite else { return 0 }
    let raw = (percent / (100.0 / Double(total))).rounded()
    return min(max(Int(raw), 0), total)
}
