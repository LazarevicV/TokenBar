import SwiftUI
import TokenBarCore

/// Menu-bar item content: the selected provider's glyph followed by its remaining session percentage.
/// Falls back to a gauge symbol while no provider has data.
struct MenuBarLabel: View {
    /// Provider whose glyph is shown; nil while nothing is loaded.
    var provider: ProviderID?
    /// Percentage left in that provider's session window.
    var sessionRemaining: Double?
    var showPercent: Bool

    private var level: UsageLevel? { sessionRemaining.map(UsageLevel.init(remaining:)) }
    private var roundedRemaining: Int? { sessionRemaining.map { Int(min(max($0, 0), 100).rounded()) } }

    var body: some View {
        HStack(spacing: 4) {
            if let provider, let image = ProviderGlyph.menuBarImage(for: provider) {
                Image(nsImage: image)
                    .renderingMode(.template)
            } else {
                Image(systemName: "gauge.with.dots.needle.33percent")
            }
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
        let name = provider.map { $0 == .claude ? "Claude" : $0 == .codex ? "Codex" : $0.rawValue }
        guard let roundedRemaining, let name else { return "TokenBar" }
        return "TokenBar, \(name) session \(roundedRemaining) percent left"
    }
}
