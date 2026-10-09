import Foundation
import Observation

/// `SettingsStoring` поверх `UserDefaults`. Значения по умолчанию: тема как в системе,
/// уведомления выключены — разрешение запрашиваем только при первом включении.
@MainActor
@Observable
final class UserDefaultsSettingsStore: SettingsStoring {
    private enum Key {
        static let appearance = "settings.appearance"
        static let notifyOnEditReady = "settings.notifyOnEditReady"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var notifyOnEditReady: Bool {
        didSet { defaults.set(notifyOnEditReady, forKey: Key.notifyOnEditReady) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearancePreference.init) ?? .system
        notifyOnEditReady = defaults.bool(forKey: Key.notifyOnEditReady)
    }
}
