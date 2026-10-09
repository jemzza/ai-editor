import Foundation

/// Слать ли уведомление: переключатель включён, приложение не активно, разрешение есть.
/// На переднем плане не уведомляем (docs/task.md).
enum NotificationPolicy {
    static func shouldNotify(isEnabled: Bool, isAppActive: Bool, authorization: NotificationAuthorization) -> Bool {
        isEnabled && !isAppActive && authorization == .authorized
    }
}

/// Локальное уведомление «правка готова», если приложение свёрнуто.
@MainActor
final class NotificationService: EditEventHandling {
    /// Сколько символов результата идёт в текст уведомления.
    nonisolated static let previewLength = 160

    private let settings: any SettingsStoring
    private let scheduler: any LocalNotificationScheduling
    private let activity: any AppActivityProviding

    init(
        settings: any SettingsStoring,
        scheduler: any LocalNotificationScheduling,
        activity: any AppActivityProviding
    ) {
        self.settings = settings
        self.scheduler = scheduler
        self.activity = activity
    }

    func editDidFinish(editId: UUID, title: String, resultText: String) async {
        // Дешёвые проверки — до запроса статуса разрешения у системы.
        guard settings.notifyOnEditReady, !activity.isAppActive,
              NotificationPolicy.shouldNotify(isEnabled: settings.notifyOnEditReady,
                                              isAppActive: activity.isAppActive,
                                              authorization: await scheduler.authorization())
        else { return }
        await scheduler.schedule(LocalNotification(title: title, body: Self.preview(resultText), editId: editId))
    }

    /// Начало результата одной строкой, не длиннее `previewLength`.
    nonisolated static func preview(_ text: String) -> String {
        let singleLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard singleLine.count > previewLength else { return singleLine }
        return String(singleLine.prefix(previewLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
