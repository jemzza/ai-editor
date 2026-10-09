import Foundation
import Synchronization
@testable import AIEditor

/// Часы, которые двигает тест. Спать не умеют — `EditService` их только читает.
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        let offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private let current = Mutex(Instant(offset: .zero))

    var now: Instant { current.withLock { $0 } }
    var minimumResolution: Duration { .zero }

    func advance(by duration: Duration) {
        current.withLock { $0 = $0.advanced(by: duration) }
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {}
}

/// Провайдер, который перед каждым токеном двигает часы — для проверки троттлинга.
struct ClockAdvancingProvider: LLMProvider {
    let tokens: [String]
    let step: Duration
    let clock: ManualClock

    var displayName: LocalizedStringResource { "Test" }

    /// Токен — только когда потребитель его попросил: часы двигаются в такт чтению.
    func streamReply(to messages: [LLMMessage]) -> AsyncThrowingStream<String, Error> {
        let remaining = Mutex(tokens[...])
        let clock = clock
        let step = step
        return AsyncThrowingStream {
            guard let token = remaining.withLock({ $0.popFirst() }) else { return nil }
            clock.advance(by: step)
            return token
        }
    }
}

/// Репозиторий-обёртка: всё передаёт дальше и запоминает статусы `updateResult`.
final class RecordingRepository: EditRepository {
    let base: any EditRepository
    private let updates = Mutex<[EditStatus]>([])

    init(base: any EditRepository) {
        self.base = base
    }

    var updateStatuses: [EditStatus] { updates.withLock { $0 } }

    func observeHistory() -> AsyncStream<[Edit]> { base.observeHistory() }
    func observeSidebar() -> AsyncStream<SidebarSnapshot> { base.observeSidebar() }
    func observeEdit(id: UUID) -> AsyncStream<Edit?> { base.observeEdit(id: id) }
    func insert(_ edit: Edit) async throws { try await base.insert(edit) }
    func updateResult(id: UUID, text: String, status: EditStatus, failure: EditFailure?,
                      updatedAt: Date) async throws {
        updates.withLock { $0.append(status) }
        try await base.updateResult(id: id, text: text, status: status, failure: failure, updatedAt: updatedAt)
    }
    func rename(id: UUID, title: String) async throws { try await base.rename(id: id, title: title) }
    func delete(id: UUID) async throws { try await base.delete(id: id) }
    func move(id: UUID, toFolder folderId: UUID?) async throws { try await base.move(id: id, toFolder: folderId) }
    func deleteAll() async throws { try await base.deleteAll() }
    func claimRetry(id: UUID) async throws -> Bool { try await base.claimRetry(id: id) }
    func markStreamingAsInterrupted() async throws -> Int { try await base.markStreamingAsInterrupted() }
    func createFolder(id: UUID, name: String, createdAt: Date) async throws {
        try await base.createFolder(id: id, name: name, createdAt: createdAt)
    }
    func renameFolder(id: UUID, name: String) async throws { try await base.renameFolder(id: id, name: name) }
    func deleteFolder(id: UUID) async throws { try await base.deleteFolder(id: id) }
    func moveFolder(id: UUID, to index: Int) async throws { try await base.moveFolder(id: id, to: index) }
}

/// Фоновые задачи под контролем теста: можно «забрать время» у генерации.
@MainActor
final class ManualBackgroundTasks: BackgroundTaskScheduling {
    private var expirations: [Int: @MainActor () -> Void] = [:]
    private var nextToken = 1
    private(set) var endedTokens: [Int] = []

    var activeCount: Int { expirations.count }

    func beginTask(expiration: @escaping @MainActor () -> Void) -> Int {
        defer { nextToken += 1 }
        expirations[nextToken] = expiration
        return nextToken
    }

    func endTask(_ token: Int) {
        expirations[token] = nil
        endedTokens.append(token)
    }

    func expireAll() {
        for expiration in expirations.values { expiration() }
    }
}

/// Запоминает события «правка готова».
@MainActor
final class RecordingEventHandler: EditEventHandling {
    private(set) var finished: [(editId: UUID, title: String, resultText: String)] = []

    func editDidFinish(editId: UUID, title: String, resultText: String) async {
        finished.append((editId, title, resultText))
    }
}
