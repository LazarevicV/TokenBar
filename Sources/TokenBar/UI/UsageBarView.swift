import SwiftUI
import TokenBarCore

extension UsageLevel {
    /// Bar / menu-bar tint for this level.
    var color: Color {
        switch self {
        case .normal: return .accentColor
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

/// A ten-segment capsule bar with a trailing percentage, e.g. `███████░░░ 68%`.
struct UsageBarView: View {
    var label: String
    var percent: Double
    var segments: Int = 10

    private var level: UsageLevel { UsageLevel(percent: percent) }
    private var filled: Int { filledSegments(percent: percent, total: segments) }
    private var roundedPercent: Int { Int(min(max(percent, 0), 999).rounded()) }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { index in
                    Capsule()
                        .fill(index < filled ? level.color : Color.secondary.opacity(0.25))
                        .frame(height: 8)
                }
            }
            Text("\(roundedPercent)%")
                .font(.system(.body, design: .default).monospacedDigit())
                .foregroundStyle(level == .normal ? Color.primary : level.color)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(roundedPercent) percent")
    }
}
