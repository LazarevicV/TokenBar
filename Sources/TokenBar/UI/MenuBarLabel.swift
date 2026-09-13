import SwiftUI
import TokenBarCore

/// Menu-bar item content: gauge symbol plus optional compact remaining session percentage.
struct MenuBarLabel: View {
    /// Percentage left in the session window chosen by `Settings.menuBarProvider`.
    var sessionRemaining: Double?
    var showPercent: Bool

    private var level: UsageLevel? { sessionRemaining.map(UsageLevel.init(remaining:)) }
    private var roundedRemaining: Int? { sessionRemaining.map { Int(min(max($0, 0), 100).rounded()) } }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            if showPercent, let roundedRemaining {
                Text("\(roundedRemaining)%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
        .foregroundStyle(level.map { $0 == .normal ? Color.primary : $0.color } ?? Color.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let roundedRemaining else { return "TokenBar" }
        return "TokenBar, session \(roundedRemaining) percent left"
    }
}
