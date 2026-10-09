import Foundation

/// Автомат состояний правки: `streaming` → `done` | `cancelled` | `failed` | `interrupted`;
/// «Retry» возвращает правку в `streaming`.
enum EditStatus: String, Hashable, Sendable {
    case streaming
    case done
    case cancelled
    case failed
    case interrupted

    /// Правку в этом статусе можно перезапросить (`done` — «Regenerate»).
    /// Только `streaming` нельзя: так второй «Retry» во время генерации ничего не делает.
    var isRetryable: Bool {
        self != .streaming
    }
}

/// Одна правка: исходный текст, действие и результат. Запись в истории.
/// Появляется в хранилище сразу со статусом `streaming`, когда пользователь нажал действие.
struct Edit: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Автозаголовок по первым словам исходника (`EditTitle`), можно переименовать.
    var title: String
    /// Папка; `nil` — правка в «Recents».
    var folderId: UUID?
    let action: EditAction
    let sourceText: String
    var resultText: String
    var status: EditStatus
    /// Только при статусе `failed`.
    var failure: EditFailure?
    let createdAt: Date
    /// Последнее изменение результата — порядок в истории.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        folderId: UUID? = nil,
        action: EditAction,
        sourceText: String,
        resultText: String = "",
        status: EditStatus = .streaming,
        failure: EditFailure? = nil,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.folderId = folderId
        self.action = action
        self.sourceText = sourceText
        self.resultText = resultText
        self.status = status
        self.failure = failure
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}
