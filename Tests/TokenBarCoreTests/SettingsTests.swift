import Foundation
import Testing
@testable import TokenBarCore

@MainActor
struct SettingsTests {
    /// A throwaway defaults suite, wiped on deinit.
    final class TempDefaults {
        let suiteName = "tokenbar.tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        init() { defaults = UserDefaults(suiteName: suiteName)! }
        deinit { defaults.removePersistentDomain(forName: suiteName) }
    }

    @Test func defaultsWhenNothingStored() {
        let temp = TempDefaults()
        let settings = Settings(defaults: temp.defaults)
        #expect(settings.refreshInterval == 60)
        #expect(settings.showPercentInMenuBar == true)
        #expect(settings.enabledProviders == [.claude, .codex])
        #expect(settings.launchAtLoginError == nil)
    }

    @Test func persistsAcrossInstances() {
        let temp = TempDefaults()
        do {
            let settings = Settings(defaults: temp.defaults)
            settings.refreshInterval = 300
            settings.showPercentInMenuBar = false
            settings.enabledProviders = [.codex]
        }
        let reloaded = Settings(defaults: temp.defaults)
        #expect(reloaded.refreshInterval == 300)
        #expect(reloaded.showPercentInMenuBar == false)
        #expect(reloaded.enabledProviders == [.codex])
    }

    @Test func usesPrefixedKeys() {
        let temp = TempDefaults()
        let settings = Settings(defaults: temp.defaults)
        settings.refreshInterval = 30
        settings.showPercentInMenuBar = false
        settings.setEnabled(.claude, false)
        #expect(temp.defaults.double(forKey: "tokenbar.refreshInterval") == 30)
        #expect(temp.defaults.bool(forKey: "tokenbar.showPercentInMenuBar") == false)
        #expect(temp.defaults.stringArray(forKey: "tokenbar.enabledProviders") == ["codex"])
    }

    @Test func snapsDisallowedIntervals() {
        let temp = TempDefaults()
        let settings = Settings(defaults: temp.defaults)
        settings.refreshInterval = 45
        #expect(settings.refreshInterval == 30)
        settings.refreshInterval = 200
        #expect(settings.refreshInterval == 300)
        settings.refreshInterval = 1
        #expect(settings.refreshInterval == 30)
        #expect(temp.defaults.double(forKey: Settings.Keys.refreshInterval) == 30)
    }

    @Test func snapsStoredDisallowedInterval() {
        let temp = TempDefaults()
        temp.defaults.set(90.0, forKey: Settings.Keys.refreshInterval)
        let settings = Settings(defaults: temp.defaults)
        #expect(settings.refreshInterval == 60)
    }

    @Test func enableAndDisableProviders() {
        let temp = TempDefaults()
        let settings = Settings(defaults: temp.defaults)
        settings.setEnabled(.claude, false)
        #expect(settings.isEnabled(.claude) == false)
        #expect(settings.isEnabled(.codex) == true)
        settings.setEnabled(.claude, true)
        #expect(settings.enabledProviders == [.claude, .codex])
    }

    @Test func launchAtLoginStatusReadDoesNotCrash() {
        let temp = TempDefaults()
        let settings = Settings(defaults: temp.defaults)
        _ = settings.launchAtLogin
        #expect(settings.launchAtLoginError == nil)
    }
}
