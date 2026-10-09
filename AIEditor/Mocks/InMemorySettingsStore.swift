#if DEBUG
import Foundation
import Observation

/// Настройки в памяти — для превью и тестов.
@MainActor
@Observable
final class InMemorySettingsStore: SettingsStoring {
    var appearance: AppearancePreference
    var notifyOnEditReady: Bool

    init(appearance: AppearancePreference = .system, notifyOnEditReady: Bool = false) {
        self.appearance = appearance
        self.notifyOnEditReady = notifyOnEditReady
    }
}
#endif
