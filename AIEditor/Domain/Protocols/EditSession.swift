import Foundation

/// Живой текст результата, который сейчас стримится. Существует только в памяти
/// (исключение из offline-first): ViewModel накладывает его поверх правки
/// со статусом `streaming`, пока в базе лежит более старая версия текста.
struct StreamingDraft: Hashable, Sendable {
    let editId: UUID
    let text: String
}

/// То, что экранам нужно от `EditService` сверх чтения из `EditRepository`.
/// Реализации: `EditService` (приложение) и `PreviewEditSession` (превью).
@MainActor
protocol EditSession: AnyObject {
    /// Черновик стримящегося результата правки: текущее значение сразу, дальше — при каждом токене.
    /// `nil` — эта правка сейчас не генерируется.
    func draftUpdates(editId: UUID) -> AsyncStream<StreamingDraft?>

    /// Создаёт правку (`streaming`) и запускает генерацию; генерацией владеет сервис.
    /// Сеть заранее не проверяется: без сети правка станет `failed(offline)` с «Retry».
    /// - Returns: id новой правки.
    func start(_ action: EditAction, source: String, inFolder folderId: UUID?) async throws -> UUID

    /// «Stop»: отменяет генерацию; полученный текст сохраняется со статусом `cancelled`.
    func stop(editId: UUID)

    /// «Retry» / «Regenerate»: перезапрашивает результат той же правки.
    /// Повторное нажатие во время генерации ничего не делает (`EditRepository.claimRetry`).
    func retry(editId: UUID) async throws

    /// Удаляет правку и отменяет её генерацию, если она идёт.
    func delete(id: UUID) async throws

    /// «Delete all history»: отменяет все генерации и удаляет все правки и папки.
    func deleteAll() async throws
}

extension EditSession {
    func start(_ action: EditAction, source: String) async throws -> UUID {
        try await start(action, source: source, inFolder: nil)
    }
}
