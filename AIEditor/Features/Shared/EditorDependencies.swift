import Foundation

/// Всё, из чего собираются экраны. Создаётся в `AppContainer`.
@MainActor
struct EditorDependencies {
    let repository: any EditRepository
    let session: any EditSession
    /// Сравнение «было — стало» (режим Compare).
    let diff: any WordDiffing
    /// Для баннера «No connection».
    let connectivity: any ConnectivityMonitoring
    /// Озвучка результата («Read aloud»).
    let speech: any SpeechSynthesizing
    /// Диктовка в поле исходного текста: запись голоса и её распознавание.
    let recorder: any VoiceRecording
    let transcriber: any SpeechTranscribing
    /// Подпись сервиса и модели («Groq · <model>») — экран Privacy.
    let modelName: LocalizedStringResource
    /// Настройки (экран Settings).
    let settings: any SettingsStoring
    /// Разрешение и отправка локальных уведомлений (экран Notifications).
    let notifications: any LocalNotificationScheduling
    /// Статус разрешений диктовки (экран Privacy).
    let permissions: any PermissionStatusProviding
    /// Открывает страницу приложения в системных Настройках.
    let openAppSettings: @MainActor () -> Void
}
