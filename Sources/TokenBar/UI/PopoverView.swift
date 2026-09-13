import SwiftUI
import TokenBarCore

/// The menu-bar popover: title row, one block per provider, footer with age and Quit.
struct PopoverView: View {
    var sections: [ProviderSection]
    var lastUpdated: Date?
    var isRefreshing: Bool
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void
    var onAction: ((ProviderID) -> Void)?

    static let width: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow
            Divider()
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 { Divider() }
                ProviderSectionView(
                    displayName: section.displayName,
                    status: section.status,
                    staleMessage: section.staleMessage,
                    onAction: onAction.map { handler in { handler(section.id) } }
                )
            }
            if sections.isEmpty {
                Text("No providers enabled").foregroundStyle(.secondary)
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: Self.width)
    }

    private var titleRow: some View {
        HStack {
            Text("TokenBar").font(.headline)
            Spacer()
            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(isRefreshing)
            .help("Refresh now")
            .accessibilityLabel("Refresh")
            .keyboardShortcut("r")
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            .keyboardShortcut(",")
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 18)
    }

    private var footer: some View {
        HStack {
            // TimelineView re-renders every 5 s so "Updated 12 s ago" keeps counting while open.
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Text(updatedText(now: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit", action: onQuit)
                .keyboardShortcut("q")
        }
    }

    private func updatedText(now: Date) -> String {
        guard let lastUpdated else { return isRefreshing ? "Updating…" : "Not updated yet" }
        let formatter = ResetFormatter(now: { now })
        return "Updated \(formatter.relativeAge(since: lastUpdated))"
    }
}
