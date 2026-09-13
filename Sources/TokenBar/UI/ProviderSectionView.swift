import SwiftUI
import TokenBarCore

/// One provider block: header with plan badge, then usage bars or a status line with an action.
struct ProviderSectionView: View {
    var displayName: String
    var status: ProviderStatus
    /// Shown under the bars (with a Retry button) when `status` carries last-good data after a failed refresh.
    var staleMessage: String?
    var onAction: (() -> Void)?
    var formatter = ResetFormatter()

    static let labelWidth: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            switch status {
            case .ok(let usage):
                usageRows(usage).opacity(staleMessage == nil ? 1 : 0.6)
                if let staleMessage {
                    statusRow(buttonTitle: "Retry") {
                        Text(staleMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
            case .loading:
                statusRow {
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                }
            case .notLoggedIn:
                statusRow(buttonTitle: "Open Terminal") {
                    Text("Not signed in · open `\(cliName)` to sign in")
                }
            case .tokenExpired:
                statusRow(buttonTitle: "Open Terminal") {
                    Text("Session expired · run `\(cliName)` to refresh")
                }
            case .error(let message):
                statusRow(buttonTitle: "Retry") {
                    Text(message)
                }
            }
        }
    }

    private var cliName: String { displayName.lowercased() }

    private var header: some View {
        HStack {
            Text(displayName).font(.headline)
            Spacer()
            if case .ok(let usage) = status, let plan = usage.plan, !plan.isEmpty {
                Text(plan.capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .accessibilityLabel("\(plan.capitalized) plan")
            }
        }
    }

    @ViewBuilder
    private func usageRows(_ usage: ProviderUsage) -> some View {
        if let session = usage.session {
            row("Current session") { UsageBarView(label: "Current session", remaining: session.remaining) }
        }
        if let weekly = usage.weekly {
            row("Weekly") { UsageBarView(label: "Weekly", remaining: weekly.remaining) }
        }
        if let session = usage.session {
            resetRow(session: session, weekly: usage.weekly)
        } else if let weekly = usage.weekly {
            row("Resets") {
                Text(formatter.string(for: weekly.resetsAt))
                    .font(.body.monospacedDigit())
                Spacer(minLength: 0)
            }
        }
        if usage.session == nil, usage.weekly == nil {
            Text("No rate-limit windows reported").foregroundStyle(.secondary)
        }
        ForEach(usage.extras, id: \.self) { extra in
            Text(extra).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resetRow(session: UsageWindow, weekly: UsageWindow?) -> some View {
        let limitReached = session.percent >= 100 || (weekly?.percent ?? 0) >= 100
        let sessionReset = formatter.string(for: session.resetsAt)
        let weeklyCaption = weekly.map { "weekly resets \(formatter.string(for: $0.resetsAt))" }
        row(limitReached ? "Limit reached" : "Resets") {
            VStack(alignment: .leading, spacing: 1) {
                Text(limitReached ? "resets \(sessionReset)" : sessionReset)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(limitReached ? Color.red : Color.primary)
                if let weeklyCaption {
                    Text(weeklyCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .help(weeklyCaption ?? "")
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(label == "Limit reached" ? Color.red : Color.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
        }
    }

    private func statusRow<Content: View>(
        buttonTitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            content()
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let buttonTitle, let onAction {
                Button(buttonTitle, action: onAction)
                    .controlSize(.small)
            }
        }
    }
}
