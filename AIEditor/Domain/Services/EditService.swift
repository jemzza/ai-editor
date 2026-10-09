import Foundation

/// Исходный текст пустой или длиннее `EditLimits.maxSourceCharacters` — правку не создаём.
struct InvalidSourceText: Error, Hashable, Sendable {}

/// Ограничения правки — общие для экрана и сервиса.
enum EditLimits {
    /// Максимальная длина исходника. Узкое место — 8 000 TPM у Groq Free (docs/task.md):
    /// ~5 000 символов ≈ 1,5–2,5K токенов на вход + до 2K на ответ.
    static let maxSourceCharacters = 5000
}

/// Логика правок: старт, генерация результата, «Stop», «Retry», удаление.
///
/// - База — единственный источник правды; сервис только пишет в неё через `EditRepository`.
/// - Живой черновик результата — в памяти (`draftUpdates`), в базу текст пишется не чаще
///   `writeInterval` и один раз в конце (исключение из offline-first, см. docs/task.md).
/// - Генерацией владеет сервис (живёт в `AppContainer`), а не экран: уход с экрана её не отменяет.
/// - Сеть заранее не проверяется (`ConnectivityMonitoring` — только подсказка для UI):
///   без сети запрос падает и правка становится `failed(offline)` с «Retry».
@MainActor
final class EditService<C: Clock>: EditSession where C.Duration == Duration {
    struct Configuration: Sendable {
        /// Как часто писать стримящийся текст в базу.
        var writeInterval: Duration = .milliseconds(500)
    }

    private struct Generation {
        var text = ""
        var task: Task<Void, Never>?
        /// Система забрала фоновое время — итог `interrupted`, а не `cancelled`.
        var interruptedBySystem = false
    }

    private let repository: any EditRepository
    private let provider: any LLMProvider
    private let prompts: any PromptBuilding
    private let backgroundTasks: (any BackgroundTaskScheduling)?
    /// Уведомление «правка готова».
    private let eventHandler: (any EditEventHandling)?
    private let clock: C
    private let now: () -> Date
    private let configuration: Configuration

    /// Идущие генерации по id правки.
    private var generations: [UUID: Generation] = [:]
    private var draftObservers: [UUID: [UUID: AsyncStream<StreamingDraft?>.Continuation]] = [:]

    init(
        repository: any EditRepository,
        provider: any LLMProvider,
        prompts: any PromptBuilding,
        backgroundTasks: (any BackgroundTaskScheduling)? = nil,
        eventHandler: (any EditEventHandling)? = nil,
        clock: C,
        now: @escaping () -> Date = Date.init,
        configuration: Configuration = Configuration()
    ) {
        self.repository = repository
        self.provider = provider
        self.prompts = prompts
        self.backgroundTasks = backgroundTasks
        self.eventHandler = eventHandler
        self.clock = clock
        self.now = now
        self.configuration = configuration
    }

    /// Идёт ли сейчас генерация правки.
    func isGenerating(editId: UUID) -> Bool {
        generations[editId] != nil
    }

    // MARK: EditSession

    func draftUpdates(editId: UUID) -> AsyncStream<StreamingDraft?> {
        let (stream, continuation) = AsyncStream.makeStream(of: StreamingDraft?.self,
                                                            bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        draftObservers[editId, default: [:]][id] = continuation
        continuation.yield(draft(editId: editId))
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.draftObservers[editId]?[id] = nil }
        }
        return stream
    }

    func start(_ action: EditAction, source: String, inFolder folderId: UUID?) async throws -> UUID {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.count <= EditLimits.maxSourceCharacters
        else { throw InvalidSourceText() }
        let edit = Edit(title: EditTitle.make(from: source), folderId: folderId, action: action,
                        sourceText: source, createdAt: now())
        try await repository.insert(edit)
        startGeneration(edit: edit)
        return edit.id
    }

    func stop(editId: UUID) {
        generations[editId]?.task?.cancel()
    }

    func retry(editId: UUID) async throws {
        guard generations[editId] == nil,
              try await repository.claimRetry(id: editId),
              // Пока ждали базу, мог стартовать второй «Retry».
              generations[editId] == nil,
              let edit = await currentEdit(id: editId)
        else { return }
        startGeneration(edit: edit)
    }

    func delete(id: UUID) async throws {
        // Запоздалая запись результата получит `EditNotFound` — её глотаем в `generate`.
        generations[id]?.task?.cancel()
        try await repository.delete(id: id)
    }

    func deleteAll() async throws {
        // Запоздалые записи отменённых генераций получат `EditNotFound` — их глотаем в `generate`.
        for generation in generations.values { generation.task?.cancel() }
        try await repository.deleteAll()
    }

    // MARK: Генерация

    private func startGeneration(edit: Edit) {
        generations[edit.id] = Generation()
        let messages = prompts.messages(for: edit.action, source: edit.sourceText)
        let task = Task { [weak self] () -> Void in
            await self?.generate(editId: edit.id, title: edit.title, messages: messages)
        }
        generations[edit.id]?.task = task
        publishDraft(editId: edit.id)
    }

    private func generate(editId: UUID, title: String, messages: [LLMMessage]) async {
        let backgroundToken = backgroundTasks?.beginTask { [weak self] in
            self?.generations[editId]?.interruptedBySystem = true
            self?.generations[editId]?.task?.cancel()
        }
        defer {
            if let backgroundToken { backgroundTasks?.endTask(backgroundToken) }
        }

        var text = ""
        var failure: EditFailure?
        var lastWrite: C.Instant?
        do {
            for try await delta in provider.streamReply(to: messages) {
                text += delta
                generations[editId]?.text = text
                publishDraft(editId: editId)
                let instant = clock.now
                if lastWrite.map({ $0.duration(to: instant) >= configuration.writeInterval }) ?? true {
                    lastWrite = instant
                    try await repository.updateResult(id: editId, text: text, status: .streaming,
                                                      failure: nil, updatedAt: now())
                }
            }
        } catch is EditNotFound {
            // Правку удалили во время генерации — писать некуда.
            finishGeneration(editId: editId)
            return
        } catch let error as LLMError {
            failure = EditFailure(kind: error.kind, retryAt: error.retryAfter.map { retryDate(after: $0) })
        } catch {
            // Отмена (в т.ч. `CancellationError` из базы) — это «Stop», а не ошибка.
            if !Task.isCancelled { failure = EditFailure(kind: .unknown) }
        }

        let status: EditStatus
        if generations[editId]?.interruptedBySystem == true {
            status = .interrupted
            failure = nil
        } else if failure != nil {
            status = .failed
        } else {
            status = Task.isCancelled ? .cancelled : .done
        }
        // Финальная запись — в отдельной задаче: отменённая генерация («Stop») сама
        // записать уже не может, а частичный текст должен сохраниться.
        let repository = repository
        let finalFailure = failure
        let finishedAt = now()
        let saved = await Task {
            do {
                try await repository.updateResult(id: editId, text: text, status: status,
                                                  failure: finalFailure, updatedAt: finishedAt)
                return true
            } catch {
                // `EditNotFound` — правка удалена; прочее — она останется `streaming`
                // и при следующем запуске станет `interrupted`.
                return false
            }
        }.value
        // Уведомление — пока фоновое время ещё наше (`endTask` — в `defer`).
        if saved, status == .done, !text.isEmpty {
            await eventHandler?.editDidFinish(editId: editId, title: title, resultText: text)
        }
        finishGeneration(editId: editId)
    }

    private func finishGeneration(editId: UUID) {
        generations[editId] = nil
        publishDraft(editId: editId)
    }

    // MARK: Вспомогательное

    private func draft(editId: UUID) -> StreamingDraft? {
        generations[editId].map { StreamingDraft(editId: editId, text: $0.text) }
    }

    private func publishDraft(editId: UUID) {
        let draft = draft(editId: editId)
        for continuation in draftObservers[editId, default: [:]].values { continuation.yield(draft) }
    }

    private func currentEdit(id: UUID) async -> Edit? {
        var edits = repository.observeEdit(id: id).makeAsyncIterator()
        return await edits.next() ?? nil
    }

    private func retryDate(after duration: Duration) -> Date {
        let (seconds, attoseconds) = duration.components
        return now().addingTimeInterval(Double(seconds) + Double(attoseconds) / 1e18)
    }
}
