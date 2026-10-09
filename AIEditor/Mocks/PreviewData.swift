#if DEBUG
import Foundation

/// Демо-данные для превью и `-mockData`: правки всех действий и во всех статусах.
/// Это пользовательский текст, а не строки интерфейса, поэтому в String Catalog не идёт.
enum PreviewData {
    static let now = Date()

    static let paraphrased = Edit(
        title: "The meeting has been moved to Thursday",
        action: .paraphrase(tone: .formal),
        sourceText: "The meeting has been moved to Thursday because half the team is out on Wednesday.",
        resultText: "The meeting has been rescheduled to Thursday, as half of the team will be unavailable on Wednesday.",
        status: .done,
        createdAt: now.addingTimeInterval(-600), updatedAt: now.addingTimeInterval(-590)
    )
    static let fixed = Edit(
        title: "Their going to the libary tomorow",
        action: .fixGrammar,
        sourceText: "Their going to the libary tomorow to study for there exam.",
        resultText: "They're going to the library tomorrow to study for their exam.",
        status: .done,
        createdAt: now.addingTimeInterval(-3_600), updatedAt: now.addingTimeInterval(-3_590)
    )
    static let translated = Edit(
        title: "Could you send me the report by Friday?",
        action: .translate(language: "de"),
        sourceText: "Could you send me the report by Friday? I need it for the board meeting.",
        resultText: "Könntest du mir den Bericht bis Freitag schicken? Ich brauche ihn für",
        status: .cancelled,
        createdAt: now.addingTimeInterval(-90_000), updatedAt: now.addingTimeInterval(-89_990)
    )
    static let rateLimited = Edit(
        title: "Our quarterly results exceeded expectations",
        action: .shorten,
        sourceText: """
            Our quarterly results exceeded expectations across all regions, driven mainly by strong \
            subscription growth in Europe and a successful product launch in Asia.
            """,
        status: .failed,
        failure: EditFailure(kind: .rateLimited, retryAt: now.addingTimeInterval(30)),
        createdAt: now.addingTimeInterval(-200_000)
    )
    static let offline = Edit(
        title: "Please find attached the updated contract",
        action: .paraphrase(tone: nil),
        sourceText: "Please find attached the updated contract with the changes we discussed.",
        status: .failed,
        failure: EditFailure(kind: .offline),
        createdAt: now.addingTimeInterval(-400_000)
    )
    static let streaming = Edit(
        title: "I think we should consider a different approach",
        action: .shorten,
        sourceText: "I think we should consider a different approach, because the current one takes too long.",
        resultText: "We should consider a faster",
        status: .streaming,
        createdAt: now.addingTimeInterval(-3_000_000)
    )

    static let edits = [paraphrased, fixed, translated, rateLimited, offline, streaming]

    static func repository() -> InMemoryEditRepository {
        InMemoryEditRepository(edits: edits)
    }

    // MARK: Папки — для превью сайдбара

    static let workFolder = Folder(id: UUID(), name: "Work", position: 0, createdAt: now.addingTimeInterval(-500_000))
    static let studyFolder = Folder(id: UUID(), name: "Study", position: 1, createdAt: now.addingTimeInterval(-400_000))
    static let emptyFolder = Folder(id: UUID(), name: "Ideas", position: 2, createdAt: now.addingTimeInterval(-300_000))
    static let folders = [workFolder, studyFolder, emptyFolder]

    /// Те же правки, но отчёт и встреча лежат в «Work», грамматика — в «Study»,
    /// «Ideas» пустая, остальные — в «Recents».
    static func repositoryWithFolders() -> InMemoryEditRepository {
        let placement = [paraphrased.id: workFolder.id, rateLimited.id: workFolder.id, fixed.id: studyFolder.id]
        let placed = edits.map { edit in
            var edit = edit
            edit.folderId = placement[edit.id]
            return edit
        }
        return InMemoryEditRepository(folders: folders, edits: placed)
    }
}
#endif
