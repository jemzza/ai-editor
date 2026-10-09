import Foundation
import Observation

/// Настройки пользователя. Хранятся вне базы (`UserDefaults`, см. docs/task.md):
/// это не данные правок, и они нужны раньше, чем откроется база (тема окна).
@MainActor
protocol SettingsStoring: AnyObject, Observable {
    var appearance: AppearancePreference { get set }
    /// Уведомлять о готовой правке, пока приложение не активно.
    var notifyOnEditReady: Bool { get set }
}
