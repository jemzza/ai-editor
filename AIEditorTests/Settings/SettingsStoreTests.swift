import Foundation
import Testing
@testable import AIEditor

@MainActor
struct SettingsStoreTests {
    /// Отдельный набор `UserDefaults` на каждый тест — не трогаем настройки приложения.
    private let suiteName = "SettingsStoreTests.\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    @Test func defaultsFollowSystemAndKeepNotificationsOff() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSettingsStore(defaults: defaults)

        #expect(store.appearance == .system)
        #expect(store.notifyOnEditReady == false)
    }

    @Test func changesSurviveNewInstance() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSettingsStore(defaults: defaults)
        store.appearance = .dark
        store.notifyOnEditReady = true

        let reloaded = UserDefaultsSettingsStore(defaults: defaults)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.notifyOnEditReady == true)

        reloaded.notifyOnEditReady = false
        reloaded.appearance = .light
        let again = UserDefaultsSettingsStore(defaults: defaults)
        #expect(again.appearance == .light)
        #expect(again.notifyOnEditReady == false)
    }

    @Test func unknownStoredAppearanceFallsBackToSystem() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("sepia", forKey: "settings.appearance")

        #expect(UserDefaultsSettingsStore(defaults: defaults).appearance == .system)
    }
}
