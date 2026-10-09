import Foundation
import Testing
@testable import AIEditor

@MainActor
struct EditServiceTests {
    private struct Harness {
        let repository: RecordingRepository
        let provider: FakeLLMProvider
        let backgroundTasks: ManualBackgroundTasks
        let events: RecordingEventHandler
        let service: EditService<ManualClock>
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_000_000)

    private func makeHarness(
        script: FakeLLMProvider.Script = .reply("Hello world", tokenDelay: .zero),
        provider customProvider: (any LLMProvider)? = nil,
        clock: ManualClock = ManualClock()
    ) throws -> Harness {
        let repository = RecordingRepository(base: GRDBEditRepository(database: try AppDatabase.inMemory()))
        let provider = FakeLLMProvider(script: script)
        let backgroundTasks = ManualBackgroundTasks()
        let events = RecordingEventHandler()
        var seconds: TimeInterval = 0
        let service = EditService(
            repository: repository,
            provider: customProvider ?? provider,
            prompts: StubPromptBuilder(),
            backgroundTasks: backgroundTasks,
            eventHandler: events,
            clock: clock,
            now: {
                // Время идёт вперёд на секунду при каждом вызове.
                seconds += 1
                return Self.fixedNow.addingTimeInterval(seconds)
            }
        )
        return Harness(repository: repository, provider: provider, backgroundTasks: backgroundTasks,
                       events: events, service: service)
    }

    private func edit(
        _ harness: Harness,
        id: UUID,
        where predicate: @escaping @Sendable (Edit?) -> Bool
    ) async throws -> Edit {
        try #require(try await firstValue(of: harness.repository.observeEdit(id: id), where: predicate))
    }

    // MARK: Старт

    @Test func startCreatesEditAndStreamsResultToDone() async throws {
        let harness = try makeHarness()

        let id = try await harness.service.start(.fixGrammar, source: "Their going home")

        let done = try await edit(harness, id: id) { $0?.status == .done }
        #expect(done.resultText == "Hello world")
        #expect(done.sourceText == "Their going home")
        #expect(done.action == .fixGrammar)
        #expect(done.title == "Their going home")
        #expect(harness.provider.requests == [StubPromptBuilder().messages(for: .fixGrammar, source: "Their going home")])
        try await waitUntil { !harness.service.isGenerating(editId: id) }
        #expect(harness.backgroundTasks.activeCount == 0)
        #expect(harness.events.finished.map(\.editId) == [id])
        #expect(harness.events.finished.first?.resultText == "Hello world")
    }

    @Test func startRejectsEmptyOrTooLongSource() async throws {
        let harness = try makeHarness()

        await #expect(throws: InvalidSourceText.self) {
            _ = try await harness.service.start(.shorten, source: " \n ")
        }
        let tooLong = String(repeating: "a", count: EditLimits.maxSourceCharacters + 1)
        await #expect(throws: InvalidSourceText.self) {
            _ = try await harness.service.start(.shorten, source: tooLong)
        }
        #expect(harness.provider.requests.isEmpty)
        #expect(try await firstValue(of: harness.repository.observeHistory()).isEmpty)
    }

    @Test func draftGrowsByTokensAndClearsAtTheEnd() async throws {
        let harness = try makeHarness(script: .reply("one two three", tokenDelay: .milliseconds(20)))

        let id = try await harness.service.start(.shorten, source: "Count")
        var drafts = harness.service.draftUpdates(editId: id).makeAsyncIterator()

        var texts: [String] = []
        while let draft = await drafts.next() {
            guard let draft else { break }
            texts.append(draft.text)
        }
        #expect(texts.last == "one two three")
        #expect(texts.contains("one "))
    }

    // MARK: Троттлинг

    /// Часы стоят: в базу — только первый токен и финальная запись.
    @Test func streamingWritesAreThrottled() async throws {
        let harness = try makeHarness(script: .reply("a b c d e f g h", tokenDelay: .zero))

        let id = try await harness.service.start(.shorten, source: "Go")
        _ = try await edit(harness, id: id) { $0?.status == .done }

        #expect(harness.repository.updateStatuses == [.streaming, .done])
    }

    /// Токен каждые 300 мс при интервале 500 мс: пишем на 1-м, 3-м и 5-м токене + финал.
    @Test func streamingWritesFollowClock() async throws {
        let clock = ManualClock()
        let provider = ClockAdvancingProvider(tokens: ["1 ", "2 ", "3 ", "4 ", "5"], step: .milliseconds(300),
                                              clock: clock)
        let harness = try makeHarness(provider: provider, clock: clock)

        let id = try await harness.service.start(.shorten, source: "Go")
        let done = try await edit(harness, id: id) { $0?.status == .done }

        #expect(harness.repository.updateStatuses == [.streaming, .streaming, .streaming, .done])
        #expect(done.resultText == "1 2 3 4 5")
    }

    // MARK: Stop, ошибки, Retry

    @Test func stopKeepsPartialTextAsCancelled() async throws {
        let full = "one two three four five six seven eight"
        let harness = try makeHarness(script: .reply(full, tokenDelay: .milliseconds(30)))
        let id = try await harness.service.start(.shorten, source: "Count")

        var drafts = harness.service.draftUpdates(editId: id).makeAsyncIterator()
        while let draft = await drafts.next() {
            if let draft, draft.text.hasPrefix("one two") { break }
        }
        harness.service.stop(editId: id)

        let cancelled = try await edit(harness, id: id) { $0?.status == .cancelled }
        #expect(cancelled.resultText.hasPrefix("one two"))
        #expect(cancelled.resultText != full)
        #expect(cancelled.failure == nil)
        try await waitUntil { !harness.service.isGenerating(editId: id) }
        // «Правка готова» — только для `done`.
        #expect(harness.events.finished.isEmpty)
    }

    @Test func providerErrorMarksFailedWithRetryDate() async throws {
        let error = LLMError(kind: .rateLimited, retryAfter: .seconds(30))
        let harness = try makeHarness(script: .fail(error, partialText: "Half ", tokenDelay: .zero))

        let id = try await harness.service.start(.shorten, source: "Go")

        let failed = try await edit(harness, id: id) { $0?.status == .failed }
        #expect(failed.resultText == "Half ")
        let failure = try #require(failed.failure)
        #expect(failure.kind == .rateLimited)
        // Время в тесте идёт по секунде за вызов: `retry-after` отсчитан от момента ошибки.
        let retryAt = try #require(failure.retryAt)
        #expect(retryAt.timeIntervalSince(failed.createdAt) > 30)
        #expect(retryAt.timeIntervalSince(failed.createdAt) < 40)
    }

    /// Без сети запрос всё равно уходит (монитор — только подсказка) и правка становится
    /// `failed(offline)` с «Retry».
    @Test func offlineErrorIsFailedOffline() async throws {
        let harness = try makeHarness(script: .fail(LLMError(kind: .offline), tokenDelay: .zero))

        let id = try await harness.service.start(.paraphrase(tone: nil), source: "Go")

        let failed = try await edit(harness, id: id) { $0?.status == .failed }
        #expect(failed.failure == EditFailure(kind: .offline))
        #expect(harness.provider.requests.count == 1)
    }

    @Test func doubleRetryStartsOneGeneration() async throws {
        let harness = try makeHarness(script: .fail(LLMError(kind: .server), tokenDelay: .zero))
        let id = try await harness.service.start(.shorten, source: "Go")
        _ = try await edit(harness, id: id) { $0?.status == .failed }
        try await waitUntil { !harness.service.isGenerating(editId: id) }
        harness.provider.setScript(.reply("Recovered", tokenDelay: .milliseconds(20)))

        async let first: Void = harness.service.retry(editId: id)
        async let second: Void = harness.service.retry(editId: id)
        _ = try await (first, second)

        let done = try await edit(harness, id: id) { $0?.status == .done }
        #expect(done.resultText == "Recovered")
        #expect(harness.provider.requests.count == 2)
        #expect(try await firstValue(of: harness.repository.observeHistory()).count == 1)
    }

    /// «Regenerate»: та же правка получает новый результат с тем же промптом.
    @Test func regenerateReplacesDoneResultInPlace() async throws {
        let harness = try makeHarness(script: .reply("First", tokenDelay: .zero))
        let id = try await harness.service.start(.translate(language: "de"), source: "Hello")
        _ = try await edit(harness, id: id) { $0?.status == .done }
        try await waitUntil { !harness.service.isGenerating(editId: id) }
        harness.provider.setScript(.reply("Second", tokenDelay: .zero))

        try await harness.service.retry(editId: id)

        let done = try await edit(harness, id: id) { $0?.status == .done && $0?.resultText == "Second" }
        #expect(done.action == .translate(language: "de"))
        #expect(harness.provider.requests.count == 2)
        #expect(harness.provider.requests.first == harness.provider.requests.last)
    }

    // MARK: Удаление и фон

    @Test func deletingEditCancelsGeneration() async throws {
        let harness = try makeHarness(script: .hang)
        let id = try await harness.service.start(.shorten, source: "Go")
        #expect(harness.service.isGenerating(editId: id))

        try await harness.service.delete(id: id)

        try await waitUntil { !harness.service.isGenerating(editId: id) }
        #expect(try await firstValue(of: harness.repository.observeHistory()).isEmpty)
    }

    @Test func deleteAllCancelsEveryGenerationAndEmptiesRepository() async throws {
        let harness = try makeHarness(script: .hang)
        let first = try await harness.service.start(.shorten, source: "One")
        let second = try await harness.service.start(.fixGrammar, source: "Two")
        #expect(harness.service.isGenerating(editId: first))
        #expect(harness.service.isGenerating(editId: second))

        try await harness.service.deleteAll()

        try await waitUntil {
            !harness.service.isGenerating(editId: first) && !harness.service.isGenerating(editId: second)
        }
        #expect(try await firstValue(of: harness.repository.observeHistory()).isEmpty)
        #expect(harness.backgroundTasks.activeCount == 0)
    }

    /// Правку удалили в обход сервиса — запоздавшая запись получает `EditNotFound` и глотается.
    @Test func lateWriteToDeletedEditIsSwallowed() async throws {
        let harness = try makeHarness(script: .hang)
        let id = try await harness.service.start(.shorten, source: "Go")
        try await waitUntil { harness.provider.requests.count == 1 }

        try await harness.repository.delete(id: id)
        harness.service.stop(editId: id)

        try await waitUntil { !harness.service.isGenerating(editId: id) }
        #expect(harness.repository.updateStatuses == [.cancelled])
        #expect(harness.backgroundTasks.activeCount == 0)
    }

    @Test func backgroundExpirationMarksInterrupted() async throws {
        let harness = try makeHarness(script: .hang)
        let id = try await harness.service.start(.shorten, source: "Go")
        try await waitUntil { harness.provider.requests.count == 1 }
        #expect(harness.backgroundTasks.activeCount == 1)

        harness.backgroundTasks.expireAll()

        let interrupted = try await edit(harness, id: id) { $0?.status == .interrupted }
        #expect(interrupted.failure == nil)
        try await waitUntil { harness.backgroundTasks.activeCount == 0 }
    }
}
