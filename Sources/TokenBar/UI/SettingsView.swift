import SwiftUI
import TokenBarCore

/// Settings window: refresh interval, menu-bar text, launch at login, enabled providers.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    var store: UsageStore?

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Refresh every", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.allowedRefreshIntervals, id: \.self) { interval in
                        Text(Self.label(for: interval)).tag(interval)
                    }
                }
                Toggle("Refresh faster while Claude or Codex are in use", isOn: $settings.refreshWhileActive)
            }
            Section("Menu bar") {
                Toggle("Show remaining % in menu bar", isOn: $settings.showPercentInMenuBar)
                Picker("Menu bar shows", selection: $settings.menuBarProvider) {
                    ForEach(MenuBarProvider.allCases, id: \.self) { choice in
                        Text(Self.label(for: choice)).tag(choice)
                    }
                }
                .disabled(!settings.showPercentInMenuBar)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Providers") {
                providerToggle("Claude", id: .claude)
                providerToggle("Codex", id: .codex)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize()
    }

    private func providerToggle(_ name: String, id: ProviderID) -> some View {
        Toggle(name, isOn: Binding(
            get: { settings.isEnabled(id) },
            set: { enabled in
                settings.setEnabled(id, enabled)
                // The store reads `enabledProviders` on each refresh; apply the change now.
                if let store {
                    Task { await store.refreshAll() }
                }
            }
        ))
    }

    static func label(for choice: MenuBarProvider) -> String {
        switch choice {
        case .lowestRemaining: return "Lowest remaining"
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    static func label(for interval: TimeInterval) -> String {
        if interval < 60 { return "\(Int(interval)) s" }
        let minutes = Int(interval / 60)
        return minutes == 1 ? "1 min" : "\(minutes) min"
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(settings: AppSettings(defaults: UserDefaults(suiteName: "preview")!))
            .previewDisplayName("Settings")
    }
}
