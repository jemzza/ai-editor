import Foundation
import GRDB

/// `EditRepository` поверх GRDB. Каждый метод записи — одна транзакция (`writer.write`),
/// поэтому проверка в `claimRetry` и само изменение атомарны.
final class GRDBEditRepository: EditRepository {
    private let writer: any DatabaseWriter
    /// Очередь, на которой GRDB доставляет значения наблюдения в `AsyncStream`.
    private let observationQueue = DispatchQueue(label: "GRDBEditRepository.observation")

    init(database: AppDatabase) {
        writer = database.writer
    }

    /// Репозиторий для запуска приложения: правки, которые стримились, когда процесс
    /// умер, переводятся в `interrupted` раньше, чем кто-то подпишется на базу.
    static func launch(database: AppDatabase) async throws -> GRDBEditRepository {
        let repository = GRDBEditRepository(database: database)
        try await repository.markStreamingAsInterrupted()
        return repository
    }

    // MARK: Наблюдение

    func observeHistory() -> AsyncStream<[Edit]> {
        observe { db in
            try EditRecord.byLastActivity().fetchAll(db).map { try $0.edit() }
        }
    }

    func observeSidebar() -> AsyncStream<SidebarSnapshot> {
        observe { db in
            // Одно чтение — согласованный снимок папок и правок.
            SidebarSnapshot(
                folders: try FolderRecord.ordered().fetchAll(db).map(\.folder),
                edits: try EditRecord.byLastActivity().fetchAll(db).map { try $0.edit() }
            )
        }
    }

    func observeEdit(id: UUID) -> AsyncStream<Edit?> {
        observe { db in
            try EditRecord.fetchOne(db, key: id)?.edit()
        }
    }

    /// Первое значение — сразу после подписки, дальше — после каждой транзакции,
    /// затронувшей прочитанные таблицы (одинаковые снимки подряд отбрасываются).
    /// Ошибка чтения завершает поток. Отмена потребителя останавливает наблюдение.
    private func observe<Value: Equatable & Sendable>(
        _ fetch: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncStream<Value> {
        let observation = ValueObservation.trackingConstantRegion(fetch).removeDuplicates()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let cancellable = observation.start(
                in: writer,
                scheduling: .async(onQueue: observationQueue),
                onError: { _ in continuation.finish() },
                onChange: { continuation.yield($0) }
            )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    // MARK: Правки

    func insert(_ edit: Edit) async throws {
        let record = EditRecord(edit)
        try await writer.write { db in
            try Self.requireFolder(record.folderId, db)
            try record.insert(db)
        }
    }

    func updateResult(id: UUID, text: String, status: EditStatus, failure: EditFailure?,
                      updatedAt: Date) async throws {
        let changed = try await writer.write { db in
            try EditRecord.filter(key: id).updateAll(db, [
                EditRecord.Columns.resultText.set(to: text),
                EditRecord.Columns.status.set(to: status.rawValue),
                EditRecord.Columns.failureKind.set(to: failure?.kind.rawValue),
                EditRecord.Columns.failureRetryAt.set(to: failure?.retryAt?.databaseTimestamp),
                EditRecord.Columns.updatedAt.set(to: updatedAt.databaseTimestamp),
            ])
        }
        guard changed > 0 else { throw EditNotFound(id: id) }
    }

    func rename(id: UUID, title: String) async throws {
        let changed = try await writer.write { db in
            try EditRecord.filter(key: id).updateAll(db, EditRecord.Columns.title.set(to: title))
        }
        guard changed > 0 else { throw EditNotFound(id: id) }
    }

    func delete(id: UUID) async throws {
        _ = try await writer.write { db in
            try EditRecord.deleteOne(db, key: id)
        }
    }

    func move(id: UUID, toFolder folderId: UUID?) async throws {
        try await writer.write { db in
            guard try EditRecord.exists(db, key: id) else { throw EditNotFound(id: id) }
            // Проверяем сами, а не ждём ошибку FK, — наружу уходит доменная ошибка.
            try Self.requireFolder(folderId, db)
            try EditRecord.filter(key: id).updateAll(db, EditRecord.Columns.folderId.set(to: folderId))
        }
    }

    func deleteAll() async throws {
        try await writer.write { db in
            _ = try EditRecord.deleteAll(db)
            _ = try FolderRecord.deleteAll(db)
        }
    }

    // MARK: Повтор и старт

    func claimRetry(id: UUID) async throws -> Bool {
        try await writer.write { db in
            guard let stored = try EditRecord.fetchOne(db, key: id) else { throw EditNotFound(id: id) }
            guard EditStatus(rawValue: stored.status)?.isRetryable == true else { return false }
            try EditRecord.filter(key: id).updateAll(db, [
                EditRecord.Columns.status.set(to: EditStatus.streaming.rawValue),
                EditRecord.Columns.resultText.set(to: ""),
                EditRecord.Columns.failureKind.set(to: nil),
                EditRecord.Columns.failureRetryAt.set(to: nil),
            ])
            return true
        }
    }

    @discardableResult
    func markStreamingAsInterrupted() async throws -> Int {
        try await writer.write { db in
            try EditRecord
                .filter(EditRecord.Columns.status == EditStatus.streaming.rawValue)
                .updateAll(db, EditRecord.Columns.status.set(to: EditStatus.interrupted.rawValue))
        }
    }

    // MARK: Папки

    func createFolder(id: UUID, name: String, createdAt: Date) async throws {
        try await writer.write { db in
            let count = try FolderRecord.fetchCount(db)
            try FolderRecord(id: id, name: name, position: count, createdAt: createdAt).insert(db)
        }
    }

    func renameFolder(id: UUID, name: String) async throws {
        let changed = try await writer.write { db in
            try FolderRecord.filter(key: id).updateAll(db, FolderRecord.Columns.name.set(to: name))
        }
        guard changed > 0 else { throw FolderNotFound(id: id) }
    }

    func deleteFolder(id: UUID) async throws {
        try await writer.write { db in
            // Правки возвращает в «Recents» `ON DELETE SET NULL`.
            guard try FolderRecord.deleteOne(db, key: id) else { return }
            try Self.renumberFolders(try FolderRecord.ordered().fetchAll(db).map(\.id), db)
        }
    }

    func moveFolder(id: UUID, to index: Int) async throws {
        try await writer.write { db in
            var ids = try FolderRecord.ordered().fetchAll(db).map(\.id)
            guard let current = ids.firstIndex(of: id) else { throw FolderNotFound(id: id) }
            ids.remove(at: current)
            ids.insert(id, at: min(max(index, 0), ids.count))
            try Self.renumberFolders(ids, db)
        }
    }

    // MARK: Внутреннее

    /// `nil` — «Recents», проверять нечего.
    private static func requireFolder(_ folderId: UUID?, _ db: Database) throws {
        guard let folderId else { return }
        guard try FolderRecord.exists(db, key: folderId) else { throw FolderNotFound(id: folderId) }
    }

    /// Позиции 0..n-1 в порядке `ids`; пишем только изменившиеся.
    private static func renumberFolders(_ ids: [UUID], _ db: Database) throws {
        let current = Dictionary(uniqueKeysWithValues: try FolderRecord.fetchAll(db).map { ($0.id, $0.position) })
        for (position, id) in ids.enumerated() where current[id] != position {
            try FolderRecord.filter(key: id).updateAll(db, FolderRecord.Columns.position.set(to: position))
        }
    }
}

extension Date {
    /// Значение даты в SQL-аргументах — в том же виде, что и в колонках записей.
    var databaseTimestamp: Double { timeIntervalSinceReferenceDate }
}
