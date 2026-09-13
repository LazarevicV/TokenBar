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

/// A ten-segment capsule bar showing what is *left* in a window, with a trailing
/// percentage, e.g. `███████░░░ 68% left`. A full bar means plenty left; empty means exhausted.
struct UsageBarView: View {
    var label: String
    /// Percentage remaining in the window (see `UsageWindow.remaining`).
    var remaining: Double
    var segments: Int = 10

    private var level: UsageLevel { UsageLevel(remaining: remaining) }
    private var filled: Int { filledSegments(remaining: remaining, total: segments) }
    private var roundedRemaining: Int { Int(min(max(remaining, 0), 100).rounded()) }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { index in
                    Capsule()
                        .fill(index < filled ? level.color : Color.secondary.opacity(0.25))
                        .frame(height: 8)
                }
            }
            Text("\(roundedRemaining)% left")
                .font(.system(.body, design: .default).monospacedDigit())
                .foregroundStyle(level == .normal ? Color.primary : level.color)
                .frame(width: 66, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(roundedRemaining) percent left")
    }
}
