import Foundation
import Observation

/// ЗАГЛУШКА экрана Editor (полная версия — ветка C, docs/plan.md): исходный текст,
/// режим, запуск через `EditSession`, результат из базы + живой черновик, Stop / Retry / Copy.
/// Нужна, чтобы навигация и история работали в шаблоне.
@MainActor
@Observable
final class EditorViewModel {
    /// `nil` — новая правка, ещё не запущенная.
    private(set) var editId: UUID?
    /// Правка из базы.
    private(set) var edit: Edit?
    /// Живой текст генерации поверх `edit.resultText`.
    private(set) var draft: StreamingDraft?
    var sourceText = ""
    var mode = EditAction.Kind.paraphrase
    private(set) var startFailed = false

    @ObservationIgnored private let repository: any EditRepository
    @ObservationIgnored private let session: any EditSession
    @ObservationIgnored private let onEditCreated: (UUID) -> Void
    @ObservationIgnored private let copyToClipboard: (String) -> Void

    init(
        editId: UUID?,
        repository: any EditRepository,
        session: any EditSession,
        onEditCreated: @escaping (UUID) -> Void = { _ in },
        copyToClipboard: @escaping (String) -> Void = { _ in }
    ) {
        self.editId = editId
        self.repository = repository
        self.session = session
        self.onEditCreated = onEditCreated
        self.copyToClipboard = copyToClipboard
    }

    var resultText: String { draft?.text ?? edit?.resultText ?? "" }
    var isGenerating: Bool { draft != nil || edit?.status == .streaming }
    var canStart: Bool {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && sourceText.count <= EditLimits.maxSourceCharacters && !isGenerating
    }

    /// Подписка на правку и её черновик; перезапускается при смене `editId` (`.task(id:)`).
    func observe() async {
        guard let editId else { return }
        async let edits: Void = observeEdit(id: editId)
        async let drafts: Void = observeDraft(id: editId)
        _ = await (edits, drafts)
    }

    private func observeEdit(id: UUID) async {
        for await edit in repository.observeEdit(id: id) {
            self.edit = edit
            if let edit, sourceText.isEmpty { sourceText = edit.sourceText }
        }
    }

    private func observeDraft(id: UUID) async {
        for await draft in session.draftUpdates(editId: id) {
            self.draft = draft
        }
    }

    func start() async {
        guard canStart else { return }
        do {
            let id = try await session.start(Self.action(for: mode), source: sourceText)
            editId = id
            onEditCreated(id)
        } catch {
            startFailed = true
        }
    }

    func stop() {
        guard let editId else { return }
        session.stop(editId: editId)
    }

    func retry() async {
        guard let editId else { return }
        try? await session.retry(editId: editId)
    }

    func copyResult() {
        copyToClipboard(resultText)
    }

    func dismissStartFailure() {
        startFailed = false
    }

    /// Заглушка: параметры по умолчанию (тон и язык выбирает полная версия экрана).
    private static func action(for kind: EditAction.Kind) -> EditAction {
        switch kind {
        case .paraphrase: .paraphrase(tone: nil)
        case .shorten: .shorten
        case .translate: .translate(language: "en")
        case .fixGrammar: .fixGrammar
        }
    }
}
