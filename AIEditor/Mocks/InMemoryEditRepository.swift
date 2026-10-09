#if DEBUG
import Foundation
import Synchronization

/// Репозиторий в памяти с тем же контрактом, что и GRDB-реализация
/// (проверяется общими контрактными тестами). Для превью, DEBUG-хука `-mockData` и тестов.
final class InMemoryEditRepository: EditRepository {
    private struct StoredEdit {
        var edit: Edit
        /// Порядок вставки — аналог rowid для сортировки при равных датах.
        let sequence: Int
    }

    private struct EditObserver {
        let editId: UUID
        let continuation: AsyncStream<Edit?>.Continuation
    }

    private struct State {
        var edits: [UUID: StoredEdit] = [:]
        var folders: [UUID: Folder] = [:]
        var nextSequence = 0
        var historyObservers: [UUID: AsyncStream<[Edit]>.Continuation] = [:]
        var sidebarObservers: [UUID: AsyncStream<SidebarSnapshot>.Continuation] = [:]
        var editObservers: [UUID: EditObserver] = [:]

        var sortedEdits: [Edit] {
            edits.values
                .sorted { ($0.edit.updatedAt, $0.edit.createdAt, $0.sequence) > ($1.edit.updatedAt, $1.edit.createdAt, $1.sequence) }
                .map(\.edit)
        }

        var sortedFolders: [Folder] {
            folders.values.sorted { $0.position < $1.position }
        }

        var sidebar: SidebarSnapshot {
            SidebarSnapshot(folders: sortedFolders, edits: sortedEdits)
        }

        func requireFolder(_ folderId: UUID?) throws {
            guard let folderId else { return }
            guard folders[folderId] != nil else { throw FolderNotFound(id: folderId) }
        }

        /// Позиции 0..n-1 в порядке `ids`.
        mutating func renumberFolders(_ ids: [UUID]) {
            for (position, id) in ids.enumerated() { folders[id]?.position = position }
        }

        mutating func insert(_ edit: Edit) {
            edits[edit.id] = StoredEdit(edit: edit, sequence: nextSequence)
            nextSequence += 1
        }

        /// Рассылает свежие снимки. `yield` потокобезопасен и не вызывает код подписчика синхронно,
        /// поэтому его можно звать под замком.
        func notify(editIds: Set<UUID>? = nil) {
            let history = sortedEdits
            for continuation in historyObservers.values { continuation.yield(history) }
            let snapshot = sidebar
            for continuation in sidebarObservers.values { continuation.yield(snapshot) }
            for observer in editObservers.values where editIds?.contains(observer.editId) ?? true {
                observer.continuation.yield(edits[observer.editId]?.edit)
            }
        }
    }

    private let state = Mutex(State())

    init(folders: [Folder] = [], edits: [Edit] = []) {
        state.withLock { state in
            for folder in folders { state.folders[folder.id] = folder }
            for edit in edits { state.insert(edit) }
        }
    }

    // MARK: Наблюдение

    func observeHistory() -> AsyncStream<[Edit]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            state.withLock { state in
                state.historyObservers[id] = continuation
                continuation.yield(state.sortedEdits)
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.historyObservers.removeValue(forKey: id) }
            }
        }
    }

    func observeSidebar() -> AsyncStream<SidebarSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            state.withLock { state in
                state.sidebarObservers[id] = continuation
                continuation.yield(state.sidebar)
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.sidebarObservers.removeValue(forKey: id) }
            }
        }
    }

    func observeEdit(id editId: UUID) -> AsyncStream<Edit?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            state.withLock { state in
                state.editObservers[id] = EditObserver(editId: editId, continuation: continuation)
                continuation.yield(state.edits[editId]?.edit)
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { _ = $0.editObservers.removeValue(forKey: id) }
            }
        }
    }

    // MARK: Правки

    func insert(_ edit: Edit) async throws {
        try state.withLock { state in
            try state.requireFolder(edit.folderId)
            state.insert(edit)
            state.notify(editIds: [edit.id])
        }
    }

    func updateResult(id: UUID, text: String, status: EditStatus, failure: EditFailure?,
                      updatedAt: Date) async throws {
        try state.withLock { state in
            guard var stored = state.edits[id] else { throw EditNotFound(id: id) }
            stored.edit.resultText = text
            stored.edit.status = status
            stored.edit.failure = failure
            stored.edit.updatedAt = updatedAt
            state.edits[id] = stored
            state.notify(editIds: [id])
        }
    }

    func rename(id: UUID, title: String) async throws {
        try state.withLock { state in
            guard state.edits[id] != nil else { throw EditNotFound(id: id) }
            state.edits[id]?.edit.title = title
            state.notify(editIds: [id])
        }
    }

    func delete(id: UUID) async throws {
        state.withLock { state in
            guard state.edits.removeValue(forKey: id) != nil else { return }
            state.notify(editIds: [id])
        }
    }

    func move(id: UUID, toFolder folderId: UUID?) async throws {
        try state.withLock { state in
            guard state.edits[id] != nil else { throw EditNotFound(id: id) }
            try state.requireFolder(folderId)
            state.edits[id]?.edit.folderId = folderId
            state.notify(editIds: [id])
        }
    }

    func deleteAll() async throws {
        state.withLock { state in
            state.edits.removeAll()
            state.folders.removeAll()
            state.notify()
        }
    }

    // MARK: Повтор и старт

    func claimRetry(id: UUID) async throws -> Bool {
        try state.withLock { state in
            guard var stored = state.edits[id] else { throw EditNotFound(id: id) }
            guard stored.edit.status.isRetryable else { return false }
            stored.edit.status = .streaming
            stored.edit.resultText = ""
            stored.edit.failure = nil
            state.edits[id] = stored
            state.notify(editIds: [id])
            return true
        }
    }

    @discardableResult
    func markStreamingAsInterrupted() async throws -> Int {
        markStreamingAsInterruptedNow()
    }

    /// Синхронный вариант — для сборки `-mockData` до показа экранов.
    @discardableResult
    func markStreamingAsInterruptedNow() -> Int {
        state.withLock { state in
            let ids = state.edits.values.filter { $0.edit.status == .streaming }.map(\.edit.id)
            for id in ids { state.edits[id]?.edit.status = .interrupted }
            if !ids.isEmpty { state.notify(editIds: Set(ids)) }
            return ids.count
        }
    }

    // MARK: Папки

    func createFolder(id: UUID, name: String, createdAt: Date) async throws {
        state.withLock { state in
            state.folders[id] = Folder(id: id, name: name, position: state.folders.count, createdAt: createdAt)
            state.notify(editIds: [])
        }
    }

    func renameFolder(id: UUID, name: String) async throws {
        try state.withLock { state in
            guard state.folders[id] != nil else { throw FolderNotFound(id: id) }
            state.folders[id]?.name = name
            state.notify(editIds: [])
        }
    }

    func deleteFolder(id: UUID) async throws {
        state.withLock { state in
            guard state.folders.removeValue(forKey: id) != nil else { return }
            // Как `ON DELETE SET NULL` в GRDB.
            let moved = state.edits.values.filter { $0.edit.folderId == id }.map(\.edit.id)
            for editId in moved { state.edits[editId]?.edit.folderId = nil }
            state.renumberFolders(state.sortedFolders.map(\.id))
            state.notify(editIds: Set(moved))
        }
    }

    func moveFolder(id: UUID, to index: Int) async throws {
        try state.withLock { state in
            var ids = state.sortedFolders.map(\.id)
            guard let current = ids.firstIndex(of: id) else { throw FolderNotFound(id: id) }
            ids.remove(at: current)
            ids.insert(id, at: min(max(index, 0), ids.count))
            state.renumberFolders(ids)
            state.notify(editIds: [])
        }
    }
}
#endif
