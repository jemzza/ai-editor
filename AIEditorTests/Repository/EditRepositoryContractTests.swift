import Foundation
import Testing
@testable import AIEditor

/// Реализации `EditRepository`, на которых гоняется один и тот же контракт.
/// GRDB — на отдельной in-memory базе для каждого теста.
enum RepositoryKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case inMemory
    case grdb

    func make() -> any EditRepository {
        switch self {
        case .inMemory: InMemoryEditRepository()
        case .grdb: GRDBEditRepository(database: try! AppDatabase.inMemory())
        }
    }

    var testDescription: String { rawValue }
}

/// Фиксированное время, чтобы порядок не зависел от часов.
private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

private func makeEdit(_ title: String = "Edit", action: EditAction = .shorten, status: EditStatus = .done,
                      at seconds: TimeInterval = 0, folderId: UUID? = nil) -> Edit {
    Edit(title: title, folderId: folderId, action: action, sourceText: "Source of \(title)",
         resultText: status == .streaming ? "" : "Result of \(title)", status: status, createdAt: at(seconds))
}

@discardableResult
private func seedEdit(_ repository: any EditRepository, _ title: String = "Edit", status: EditStatus = .done,
                      at seconds: TimeInterval = 0) async throws -> Edit {
    let edit = makeEdit(title, status: status, at: seconds)
    try await repository.insert(edit)
    return edit
}

private func history(_ repository: any EditRepository,
                     where predicate: @escaping @Sendable ([Edit]) -> Bool = { _ in true }) async throws -> [Edit] {
    try await firstValue(of: repository.observeHistory(), where: predicate)
}

private func edit(_ repository: any EditRepository, id: UUID,
                  where predicate: @escaping @Sendable (Edit?) -> Bool = { _ in true }) async throws -> Edit? {
    try await firstValue(of: repository.observeEdit(id: id), where: predicate)
}

@discardableResult
private func seedFolder(_ repository: any EditRepository, _ name: String = "Folder",
                        at seconds: TimeInterval = 0) async throws -> UUID {
    let id = UUID()
    try await repository.createFolder(id: id, name: name, createdAt: at(seconds))
    return id
}

private func sidebar(_ repository: any EditRepository,
                     where predicate: @escaping @Sendable (SidebarSnapshot) -> Bool = { _ in true }) async throws -> SidebarSnapshot {
    try await firstValue(of: repository.observeSidebar(), where: predicate)
}

private extension SidebarSnapshot {
    var folderIds: [UUID] { folders.map(\.folder.id) }
    var positions: [Int] { folders.map(\.folder.position) }

    func editIds(in folderId: UUID) -> [UUID]? {
        folders.first { $0.id == folderId }?.edits.map(\.id)
    }
}

@Suite("EditRepository contract")
struct EditRepositoryContractTests {
    // MARK: Правки

    @Test(arguments: RepositoryKind.allCases)
    func insertedEditReadsBackUnchanged(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let actions: [EditAction] = [.paraphrase(tone: .casual), .paraphrase(tone: nil), .shorten,
                                     .translate(language: "de"), .fixGrammar]
        for (index, action) in actions.enumerated() {
            let original = Edit(title: "T\(index)", action: action, sourceText: "Ünïcödé\nsource",
                                resultText: "Result", status: .failed,
                                failure: EditFailure(kind: .rateLimited, retryAt: at(30.5)),
                                createdAt: at(Double(index)), updatedAt: at(Double(index) + 0.25))
            try await repository.insert(original)
            #expect(try await edit(repository, id: original.id) == original)
        }
    }

    @Test(arguments: RepositoryKind.allCases)
    func historyIsNewestFirstByUpdatedAt(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let older = try await seedEdit(repository, "Older", at: 0)
        let newer = try await seedEdit(repository, "Newer", at: 10)
        #expect(try await history(repository) { $0.count == 2 }.map(\.id) == [newer.id, older.id])

        try await repository.updateResult(id: older.id, text: "Again", status: .done, failure: nil, updatedAt: at(20))

        #expect(try await history(repository) { $0.first?.id == older.id }.map(\.id) == [older.id, newer.id])
    }

    @Test(arguments: RepositoryKind.allCases)
    func updateResultStoresTextStatusAndFailure(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let streaming = try await seedEdit(repository, status: .streaming)

        try await repository.updateResult(id: streaming.id, text: "Part", status: .failed,
                                          failure: EditFailure(kind: .offline), updatedAt: at(5))

        let stored = try #require(try await edit(repository, id: streaming.id) { $0?.status == .failed })
        #expect(stored.resultText == "Part")
        #expect(stored.failure == EditFailure(kind: .offline))
        #expect(stored.updatedAt == at(5))
        #expect(stored.sourceText == streaming.sourceText)

        let unknown = UUID()
        await #expect(throws: EditNotFound(id: unknown)) {
            try await repository.updateResult(id: unknown, text: "x", status: .done, failure: nil, updatedAt: at(1))
        }
    }

    @Test(arguments: RepositoryKind.allCases)
    func renameAndDelete(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let first = try await seedEdit(repository, "First")

        try await repository.rename(id: first.id, title: "Renamed")
        #expect(try await edit(repository, id: first.id) { $0?.title == "Renamed" }?.updatedAt == first.updatedAt)

        try await repository.delete(id: first.id)
        try await repository.delete(id: first.id)
        #expect(try await edit(repository, id: first.id) { $0 == nil } == nil)
        #expect(try await history(repository) { $0.isEmpty }.isEmpty)

        await #expect(throws: EditNotFound(id: first.id)) {
            try await repository.rename(id: first.id, title: "Gone")
        }
    }

    // MARK: Повтор и старт

    @Test(arguments: RepositoryKind.allCases, [EditStatus.failed, .interrupted, .cancelled, .done])
    func claimRetryResetsResult(kind: RepositoryKind, status: EditStatus) async throws {
        let repository = kind.make()
        let original = Edit(title: "T", action: .shorten, sourceText: "S", resultText: "Old", status: status,
                            failure: status == .failed ? EditFailure(kind: .server) : nil, createdAt: t0)
        try await repository.insert(original)

        #expect(try await repository.claimRetry(id: original.id))

        let stored = try #require(try await edit(repository, id: original.id) { $0?.status == .streaming })
        #expect(stored.resultText.isEmpty)
        #expect(stored.failure == nil)
        // Второй «Retry» во время генерации ничего не делает.
        #expect(try await repository.claimRetry(id: original.id) == false)
    }

    @Test(arguments: RepositoryKind.allCases)
    func claimRetryOfUnknownEditThrows(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let unknown = UUID()
        await #expect(throws: EditNotFound(id: unknown)) {
            _ = try await repository.claimRetry(id: unknown)
        }
    }

    @Test(arguments: RepositoryKind.allCases)
    func markStreamingAsInterruptedTouchesOnlyStreaming(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let streaming = try await seedEdit(repository, "Streaming", status: .streaming, at: 0)
        let done = try await seedEdit(repository, "Done", status: .done, at: 1)

        #expect(try await repository.markStreamingAsInterrupted() == 1)
        #expect(try await repository.markStreamingAsInterrupted() == 0)

        #expect(try await edit(repository, id: streaming.id) { $0?.status == .interrupted } != nil)
        #expect(try await edit(repository, id: done.id)?.status == .done)
    }

    // MARK: Папки и сайдбар

    @Test(arguments: RepositoryKind.allCases)
    func sidebarStartsEmptyAndNewEditGoesToRecents(kind: RepositoryKind) async throws {
        let repository = kind.make()
        #expect(try await sidebar(repository) == .empty)

        let edit = try await seedEdit(repository)

        let snapshot = try await sidebar(repository) { !$0.recents.isEmpty }
        #expect(snapshot.recents.map(\.id) == [edit.id])
        #expect(snapshot.folders.isEmpty)
    }

    @Test(arguments: RepositoryKind.allCases)
    func foldersKeepCreationOrderAndCanBeMoved(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let a = try await seedFolder(repository, "A", at: 0)
        let b = try await seedFolder(repository, "B", at: 1)
        let c = try await seedFolder(repository, "C", at: 2)
        var snapshot = try await sidebar(repository) { $0.folders.count == 3 }
        #expect(snapshot.folderIds == [a, b, c])
        #expect(snapshot.positions == [0, 1, 2])

        try await repository.moveFolder(id: c, to: 0)
        snapshot = try await sidebar(repository) { $0.folderIds == [c, a, b] }

        // За краями — зажимается.
        try await repository.moveFolder(id: c, to: 99)
        snapshot = try await sidebar(repository) { $0.folderIds == [a, b, c] }
        try await repository.moveFolder(id: c, to: -5)
        snapshot = try await sidebar(repository) { $0.folderIds == [c, a, b] }
        #expect(snapshot.positions == [0, 1, 2])

        let unknown = UUID()
        await #expect(throws: FolderNotFound(id: unknown)) {
            try await repository.moveFolder(id: unknown, to: 0)
        }
    }

    @Test(arguments: RepositoryKind.allCases)
    func renameFolder(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let folder = try await seedFolder(repository, "Work")

        try await repository.renameFolder(id: folder, name: "Projects")

        _ = try await sidebar(repository) { $0.folders.first?.folder.name == "Projects" }
        let unknown = UUID()
        await #expect(throws: FolderNotFound(id: unknown)) {
            try await repository.renameFolder(id: unknown, name: "Gone")
        }
    }

    @Test(arguments: RepositoryKind.allCases)
    func moveEditBetweenFolderAndRecents(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let folder = try await seedFolder(repository)
        let moved = try await seedEdit(repository, "Moved", at: 0)
        let other = try await seedEdit(repository, "Stays", at: 1)

        try await repository.move(id: moved.id, toFolder: folder)

        var snapshot = try await sidebar(repository) { $0.editIds(in: folder) == [moved.id] }
        #expect(snapshot.recents.map(\.id) == [other.id])
        #expect(snapshot.folders.first?.edits.first?.updatedAt == moved.updatedAt)
        // История по-прежнему видит все правки.
        #expect(Set(try await history(repository) { $0.count == 2 }.map(\.id)) == [moved.id, other.id])

        try await repository.move(id: moved.id, toFolder: nil)

        snapshot = try await sidebar(repository) { $0.recents.count == 2 }
        #expect(snapshot.recents.map(\.id) == [other.id, moved.id])
        #expect(snapshot.editIds(in: folder) == [])
    }

    @Test(arguments: RepositoryKind.allCases)
    func moveEditRejectsUnknownEditOrFolder(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let folder = try await seedFolder(repository)
        let edit = try await seedEdit(repository)

        let unknownEdit = UUID()
        await #expect(throws: EditNotFound(id: unknownEdit)) {
            try await repository.move(id: unknownEdit, toFolder: folder)
        }
        let unknownFolder = UUID()
        await #expect(throws: FolderNotFound(id: unknownFolder)) {
            try await repository.move(id: edit.id, toFolder: unknownFolder)
        }

        let snapshot = try await sidebar(repository)
        #expect(snapshot.recents.map(\.id) == [edit.id])
        #expect(snapshot.editIds(in: folder) == [])
    }

    @Test(arguments: RepositoryKind.allCases)
    func deleteFolderReturnsEditsToRecentsAndIsIdempotent(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let first = try await seedFolder(repository, "First")
        let doomed = try await seedFolder(repository, "Doomed")
        let last = try await seedFolder(repository, "Last")
        let seeded = try await seedEdit(repository)
        try await repository.move(id: seeded.id, toFolder: doomed)
        _ = try await sidebar(repository) { $0.editIds(in: doomed) == [seeded.id] }

        try await repository.deleteFolder(id: doomed)
        try await repository.deleteFolder(id: doomed)

        let snapshot = try await sidebar(repository) { $0.folders.count == 2 }
        #expect(snapshot.folderIds == [first, last])
        #expect(snapshot.positions == [0, 1])
        #expect(snapshot.recents.map(\.id) == [seeded.id])
        #expect(snapshot.recents.first?.folderId == nil)
        #expect(try await edit(repository, id: seeded.id)?.resultText == seeded.resultText)
    }

    @Test(arguments: RepositoryKind.allCases)
    func insertIntoFolderChecksFolder(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let folder = try await seedFolder(repository)
        let inFolder = makeEdit(folderId: folder)
        try await repository.insert(inFolder)
        _ = try await sidebar(repository) { $0.editIds(in: folder) == [inFolder.id] }

        let unknown = UUID()
        let orphan = makeEdit("Orphan", folderId: unknown)
        await #expect(throws: FolderNotFound(id: unknown)) {
            try await repository.insert(orphan)
        }
        #expect(try await history(repository).map(\.id) == [inFolder.id])
    }

    @Test(arguments: RepositoryKind.allCases)
    func deleteAllRemovesEditsAndFolders(kind: RepositoryKind) async throws {
        let repository = kind.make()
        let folder = try await seedFolder(repository)
        let edit = try await seedEdit(repository)
        try await repository.move(id: edit.id, toFolder: folder)
        try await seedEdit(repository, "Other", at: 1)
        _ = try await sidebar(repository) { $0.editIds(in: folder) == [edit.id] && $0.recents.count == 1 }

        try await repository.deleteAll()
        try await repository.deleteAll()

        #expect(try await sidebar(repository) { $0 == .empty } == .empty)
        #expect(try await history(repository) { $0.isEmpty }.isEmpty)
        await #expect(throws: EditNotFound(id: edit.id)) {
            try await repository.updateResult(id: edit.id, text: "x", status: .done, failure: nil, updatedAt: at(9))
        }
        // После очистки репозиторий работает как новый.
        try await seedEdit(repository, "Fresh", at: 3)
        #expect(try await history(repository) { $0.count == 1 }.map(\.title) == ["Fresh"])
    }
}
