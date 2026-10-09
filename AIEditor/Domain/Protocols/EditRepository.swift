import Foundation

/// Единственный источник правды о правках и папках.
protocol EditRepository: Sendable {
    // MARK: Наблюдение
    // Первое значение приходит сразу, дальше — при каждом изменении.

    /// Все правки (в том числе лежащие в папках), новые (по `updatedAt`) сверху.
    func observeHistory() -> AsyncStream<[Edit]>
    /// Папки по `position` с их правками + правки без папки («Recents»); внутри секций — новые сверху.
    func observeSidebar() -> AsyncStream<SidebarSnapshot>
    /// Одна правка; `nil` — её нет (удалена).
    func observeEdit(id: UUID) -> AsyncStream<Edit?>

    // MARK: Правки

    /// - Throws: `FolderNotFound`, если `edit.folderId` указывает на несуществующую папку.
    func insert(_ edit: Edit) async throws
    /// Результат и статус; `updatedAt` = `updatedAt` аргумента.
    /// - Throws: `EditNotFound`, если правки уже нет (удалена во время стрима).
    func updateResult(id: UUID, text: String, status: EditStatus, failure: EditFailure?,
                      updatedAt: Date) async throws
    /// - Throws: `EditNotFound`.
    func rename(id: UUID, title: String) async throws
    /// Отсутствующая правка — не ошибка.
    func delete(id: UUID) async throws
    /// Переносит правку в папку; `folderId == nil` — в «Recents». `updatedAt` не меняется.
    /// - Throws: `EditNotFound`, `FolderNotFound` (правка при этом остаётся где была).
    func move(id: UUID, toFolder folderId: UUID?) async throws
    /// Удаляет все правки и папки одной транзакцией («Delete all history»).
    func deleteAll() async throws

    // MARK: Повтор и старт

    /// Атомарно: правка `failed`/`interrupted`/`cancelled`/`done` → `streaming`, очищает
    /// `resultText` и `failure`.
    /// - Returns: `false`, если правка уже `streaming`.
    /// - Throws: `EditNotFound`.
    func claimRetry(id: UUID) async throws -> Bool
    /// При запуске: все `streaming` → `interrupted`.
    /// - Returns: сколько правок изменено.
    @discardableResult
    func markStreamingAsInterrupted() async throws -> Int

    // MARK: Папки

    /// Новая папка в конце списка. Имя не проверяется — это забота ViewModel.
    func createFolder(id: UUID, name: String, createdAt: Date) async throws
    /// - Throws: `FolderNotFound`.
    func renameFolder(id: UUID, name: String) async throws
    /// Удаляет папку; её правки возвращаются в «Recents», позиции остальных папок уплотняются.
    /// Отсутствующая папка — не ошибка.
    func deleteFolder(id: UUID) async throws
    /// Ставит папку на место `index` в итоговом списке (зажимается в `0..<count`),
    /// остальные сдвигаются.
    /// - Throws: `FolderNotFound`.
    func moveFolder(id: UUID, to index: Int) async throws
}
