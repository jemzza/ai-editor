import Foundation

/// Как показать ошибку правки: текст и иконка по `ErrorKind` (таблица в docs/task.md).
/// Тексты не содержат ключ, URL и сырой ответ сервера — только понятная причина.
struct EditErrorPresentation: Sendable {
    let title: LocalizedStringResource
    let systemImage: String

    init(kind: ErrorKind) {
        switch kind {
        case .offline:
            title = "No internet connection."
            systemImage = "wifi.slash"
        case .rateLimited:
            title = "The AI service rate limit was reached."
            systemImage = "hourglass"
        case .unauthorized:
            title = "The AI service rejected the API key."
            systemImage = "key"
        case .forbidden:
            title = "The AI service isn't available in your region."
            systemImage = "globe"
        case .server:
            title = "The AI service is having problems. Please try again."
            systemImage = "exclamationmark.icloud"
        case .unknown:
            title = "Something went wrong."
            systemImage = "exclamationmark.triangle"
        }
    }

    /// Генерация оборвалась: приложение закрылось во время неё.
    static let interrupted = EditErrorPresentation(
        title: "The result was interrupted.",
        systemImage: "exclamationmark.bubble"
    )

    private init(title: LocalizedStringResource, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    /// Плашка для правки, если она нужна (`failed` или `interrupted`).
    static func forEdit(_ edit: Edit) -> EditErrorPresentation? {
        switch edit.status {
        case .failed: EditErrorPresentation(kind: edit.failure?.kind ?? .unknown)
        case .interrupted: .interrupted
        case .streaming, .done, .cancelled: nil
        }
    }

    /// Сколько целых секунд ждать до повтора (429 с `retry-after`); `nil` — можно сейчас.
    static func secondsUntilRetry(_ failure: EditFailure?, now: Date) -> Int? {
        guard let retryAt = failure?.retryAt else { return nil }
        let remaining = retryAt.timeIntervalSince(now)
        return remaining > 0 ? Int(remaining.rounded(.up)) : nil
    }
}
