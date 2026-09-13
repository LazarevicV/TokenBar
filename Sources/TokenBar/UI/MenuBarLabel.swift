import SwiftUI
import TokenBarCore

/// Menu-bar item content: gauge symbol plus optional compact highest-session percentage.
struct MenuBarLabel: View {
    var highestSessionPercent: Double?
    var showPercent: Bool

    private var level: UsageLevel? { highestSessionPercent.map(UsageLevel.init(percent:)) }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            if showPercent, let percent = highestSessionPercent {
                Text("\(Int(min(max(percent, 0), 999).rounded()))%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
        .foregroundStyle(level.map { $0 == .normal ? Color.primary : $0.color } ?? Color.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let percent = highestSessionPercent else { return "TokenBar" }
        return "TokenBar, highest session usage \(Int(percent.rounded())) percent"
    }
}
