import SwiftUI
import TokenBarCore

/// Static sample data for previews.
enum SampleData {
    static let now = Date()

    static let claudeOK = ProviderSection(
        id: .claude,
        displayName: "Claude",
        status: .ok(ProviderUsage(
            provider: .claude,
            session: UsageWindow(percent: 68, resetsAt: now.addingTimeInterval(2 * 3600 + 15 * 60), label: "5h"),
            weekly: UsageWindow(percent: 41, resetsAt: now.addingTimeInterval(4 * 86_400 + 12 * 3600), label: "week"),
            plan: "pro"
        ))
    )

    static let codexOK = ProviderSection(
        id: .codex,
        displayName: "Codex",
        status: .ok(ProviderUsage(
            provider: .codex,
            session: UsageWindow(percent: 53, resetsAt: now.addingTimeInterval(30 * 3600), label: "5h"),
            weekly: UsageWindow(percent: 24, resetsAt: now.addingTimeInterval(8 * 86_400), label: "week"),
            plan: "plus"
        ))
    )

    static let codexWarning = ProviderSection(
        id: .codex,
        displayName: "Codex",
        status: .ok(ProviderUsage(
            provider: .codex,
            session: UsageWindow(percent: 78, resetsAt: now.addingTimeInterval(45 * 60), label: "5h"),
            weekly: UsageWindow(percent: 91, resetsAt: now.addingTimeInterval(3 * 86_400), label: "week"),
            plan: "plus"
        ))
    )

    static let claudeLimitReached = ProviderSection(
        id: .claude,
        displayName: "Claude",
        status: .ok(ProviderUsage(
            provider: .claude,
            session: UsageWindow(percent: 100, resetsAt: now.addingTimeInterval(3 * 3600 + 5 * 60), label: "5h"),
            weekly: UsageWindow(percent: 62, resetsAt: now.addingTimeInterval(2 * 86_400), label: "week"),
            plan: "max"
        ))
    )

    static let loading = ProviderSection(id: .claude, displayName: "Claude", status: .loading)
    static let notLoggedIn = ProviderSection(id: .codex, displayName: "Codex", status: .notLoggedIn)
    static let tokenExpired = ProviderSection(id: .codex, displayName: "Codex", status: .tokenExpired)
    static let offline = ProviderSection(
        id: .claude,
        displayName: "Claude",
        status: .error("Offline · showing data from 3 min ago")
    )

    static let stale = ProviderSection(
        id: .claude,
        displayName: "Claude",
        status: claudeOK.status,
        staleMessage: "Offline · showing data from 3 min ago"
    )

    static let sections: [ProviderSection] = [claudeOK, codexOK]
}

// `#Preview` needs the PreviewsMacros plugin, which Command Line Tools do not ship, so these
// use the macro-free `PreviewProvider` protocol. Xcode's canvas renders both the same way.

private func popover(
    _ sections: [ProviderSection],
    lastUpdated: Date? = SampleData.now.addingTimeInterval(-12),
    isRefreshing: Bool = false,
    onAction: ((ProviderID) -> Void)? = { _ in }
) -> some View {
    PopoverView(
        sections: sections,
        lastUpdated: lastUpdated,
        isRefreshing: isRefreshing,
        onRefresh: {}, onOpenSettings: {}, onQuit: {},
        onAction: onAction
    )
}

struct PopoverView_Previews: PreviewProvider {
    static var previews: some View {
        popover(SampleData.sections)
            .previewDisplayName("Popover – ok")
        popover([SampleData.claudeOK, SampleData.codexWarning],
                lastUpdated: SampleData.now.addingTimeInterval(-3 * 60), isRefreshing: true)
            .previewDisplayName("Popover – warning / critical")
        popover([SampleData.claudeLimitReached, SampleData.codexOK], lastUpdated: SampleData.now)
            .previewDisplayName("Popover – limit reached")
        popover([SampleData.loading, ProviderSection(id: .codex, displayName: "Codex", status: .loading)],
                lastUpdated: nil, isRefreshing: true)
            .previewDisplayName("Popover – loading")
        popover([SampleData.offline, SampleData.notLoggedIn],
                lastUpdated: SampleData.now.addingTimeInterval(-3 * 60))
            .previewDisplayName("Popover – error states")
        popover([SampleData.claudeOK, SampleData.tokenExpired])
            .previewDisplayName("Popover – token expired")
        popover([SampleData.stale, SampleData.codexOK])
            .previewDisplayName("Popover – stale")
        popover([], lastUpdated: nil)
            .previewDisplayName("Popover – no providers")
    }
}

struct ProviderSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ProviderSectionView(displayName: "Codex", status: .tokenExpired, onAction: {})
            .padding().frame(width: PopoverView.width)
            .previewDisplayName("Section – token expired")
        ProviderSectionView(displayName: "Claude", status: .notLoggedIn, onAction: {})
            .padding().frame(width: PopoverView.width)
            .previewDisplayName("Section – not logged in")
        ProviderSectionView(displayName: "Claude", status: .error("Offline · showing data from 3 min ago"), onAction: {})
            .padding().frame(width: PopoverView.width)
            .previewDisplayName("Section – error")
        ProviderSectionView(displayName: "Claude", status: .loading)
            .padding().frame(width: PopoverView.width)
            .previewDisplayName("Section – loading")
    }
}

struct UsageBarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Remaining percentages: plenty left, warning band (10–30), critical (< 10), exhausted.
            ForEach([100, 59, 32, 21, 12, 6, 0], id: \.self) { remaining in
                UsageBarView(label: "Current session", remaining: Double(remaining))
            }
        }
        .padding()
        .frame(width: 200)
        .previewDisplayName("Usage bars")
    }
}

struct MenuBarLabel_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            MenuBarLabel(sessionRemaining: nil, showPercent: true)
            MenuBarLabel(sessionRemaining: 32, showPercent: true)
            MenuBarLabel(sessionRemaining: 22, showPercent: true)
            MenuBarLabel(sessionRemaining: 0, showPercent: true)
            MenuBarLabel(sessionRemaining: 32, showPercent: false)
        }
        .padding()
        .previewDisplayName("Menu bar label")
    }
}
