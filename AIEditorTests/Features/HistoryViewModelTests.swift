import Foundation
import Testing
@testable import AIEditor

@MainActor
struct HistoryViewModelTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 12:00 UTC — «0,4 дня назад» остаётся в том же дне.
    private static let now = Date(timeIntervalSince1970: 1_791_288_000)

    private static func edit(_ title: String, daysAgo: Double) -> Edit {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        return Edit(title: title, action: .shorten, sourceText: "Source of \(title)", resultText: "Result",
                    status: .done, createdAt: date)
    }

    private static func folder(_ name: String, position: Int) -> Folder {
        Folder(id: UUID(), name: name, position: position, createdAt: now)
    }

    private static func edit(_ title: String, daysAgo: Double, in folder: Folder) -> Edit {
        var edit = edit(title, daysAgo: daysAgo)
        edit.folderId = folder.id
        return edit
    }

    private func makeViewModel(
        folders: [Folder] = [],
        edits: [Edit]
    ) async throws -> (HistoryViewModel, InMemoryEditRepository, Task<Void, Never>) {
        let repository = InMemoryEditRepository(folders: folders, edits: edits)
        let viewModel = HistoryViewModel(
            repository: repository,
            session: EditorDependencies.preview(repository: repository).session,
            now: { Self.now },
            calendar: Self.calendar
        )
        let observation = Task { await viewModel.observe() }
        try await waitUntil { viewModel.hasLoaded }
        return (viewModel, repository, observation)
    }

    @Test(arguments: [
        (0.0, EditDateGroup.today),
        (0.4, .today),
        (1.0, .yesterday),
        (2.0, .previous7Days),
        (7.0, .previous7Days),
        (8.0, .older),
        (400.0, .older),
    ])
    func groupsByCalendarDay(daysAgo: Double, expected: EditDateGroup) {
        let date = Self.now.addingTimeInterval(-daysAgo * 86_400)
        #expect(EditDateGroup.group(for: date, now: Self.now, calendar: Self.calendar) == expected)
    }

    @Test func sectionsSkipEmptyGroupsAndKeepOrder() async throws {
        let (viewModel, _, observation) = try await makeViewModel(edits: [
            Self.edit("Old", daysAgo: 30), Self.edit("Fresh", daysAgo: 0), Self.edit("Last week", daysAgo: 3),
        ])
        defer { observation.cancel() }

        #expect(viewModel.sections.map(\.group) == [.today, .previous7Days, .older])
        #expect(viewModel.sections.map { $0.edits.map(\.title) } == [["Fresh"], ["Last week"], ["Old"]])
    }

    @Test func openEditFromNotificationSelectsExistingEditOnly() async throws {
        let target = Self.edit("Target", daysAgo: 1)
        let (viewModel, _, observation) = try await makeViewModel(edits: [Self.edit("Other", daysAgo: 0), target])
        defer { observation.cancel() }
        viewModel.searchText = "oth"

        viewModel.openEdit(id: target.id)
        #expect(viewModel.selectedEditId == target.id)
        #expect(viewModel.searchText.isEmpty)

        viewModel.openEdit(id: UUID())
        #expect(viewModel.selectedEditId == target.id)
    }

    @Test func searchFiltersByTitleIgnoringCase() async throws {
        let (viewModel, _, observation) = try await makeViewModel(edits: [
            Self.edit("Swift actors", daysAgo: 0), Self.edit("Trip ideas", daysAgo: 1),
        ])
        defer { observation.cancel() }

        viewModel.searchText = "  SWIFT "
        #expect(viewModel.sections.flatMap(\.edits).map(\.title) == ["Swift actors"])

        viewModel.searchText = "nothing"
        #expect(viewModel.hasNoSearchResults)
        #expect(!viewModel.isEmpty)
    }

    @Test func emptyStateOnlyAfterFirstLoad() async throws {
        let repository = InMemoryEditRepository()
        let viewModel = HistoryViewModel(repository: repository, session: EditorDependencies.preview(repository: repository).session)
        #expect(!viewModel.isEmpty)

        let observation = Task { await viewModel.observe() }
        defer { observation.cancel() }
        try await waitUntil { viewModel.hasLoaded }
        #expect(viewModel.isEmpty)
    }

    @Test func renameTrimsTitleAndIgnoresBlank() async throws {
        let edit = Self.edit("Old title", daysAgo: 0)
        let (viewModel, _, observation) = try await makeViewModel(edits: [edit])
        defer { observation.cancel() }

        viewModel.beginRename(edit)
        viewModel.renameText = "   "
        #expect(!viewModel.canCommitRename)
        await viewModel.commitRename()?.value
        #expect(viewModel.renamingEdit == nil)
        #expect(viewModel.edits.first?.title == "Old title")

        viewModel.beginRename(edit)
        viewModel.renameText = "  New title \n"
        await viewModel.commitRename()?.value
        try await waitUntil { viewModel.edits.first?.title == "New title" }
    }

    @Test func deleteSelectedEditFallsBackToNewEdit() async throws {
        let first = Self.edit("First", daysAgo: 0)
        let second = Self.edit("Second", daysAgo: 1)
        let (viewModel, _, observation) = try await makeViewModel(edits: [first, second])
        defer { observation.cancel() }

        viewModel.select(first)
        viewModel.requestDelete(first)
        await viewModel.confirmDelete()?.value

        #expect(viewModel.selectedEditId == nil)
        try await waitUntil { viewModel.edits.map(\.id) == [second.id] }
        #expect(!viewModel.actionFailed)
    }

    @Test func selectionResetsWhenEditDisappears() async throws {
        let edit = Self.edit("Doomed", daysAgo: 0)
        let (viewModel, repository, observation) = try await makeViewModel(edits: [edit])
        defer { observation.cancel() }

        viewModel.select(edit)
        try await repository.delete(id: edit.id)

        try await waitUntil { viewModel.selectedEditId == nil }
    }

    @Test func createdEditKeepsScreenButSelectingAnotherReplacesIt() async throws {
        let existing = Self.edit("Existing", daysAgo: 0)
        let (viewModel, _, observation) = try await makeViewModel(edits: [existing])
        defer { observation.cancel() }

        let newEditScreen = viewModel.screenID
        viewModel.didCreateEdit(id: UUID())
        #expect(viewModel.screenID == newEditScreen)

        viewModel.select(existing)
        #expect(viewModel.screenID != newEditScreen)

        let existingScreen = viewModel.screenID
        viewModel.select(existing)
        #expect(viewModel.screenID == existingScreen)
    }

    /// Свежесозданная правка может ещё не попасть в снимок списка — выбор не сбрасываем.
    @Test func createdEditNotYetListedStaysSelected() async throws {
        let (viewModel, repository, observation) = try await makeViewModel(edits: [Self.edit("Other", daysAgo: 0)])
        defer { observation.cancel() }

        let id = UUID()
        viewModel.didCreateEdit(id: id)
        try await repository.rename(id: viewModel.edits[0].id, title: "Renamed")
        try await waitUntil { viewModel.edits.first?.title == "Renamed" }

        #expect(viewModel.selectedEditId == id)
    }

    // MARK: Папки

    @Test func editsInFoldersAreNotInRecents() async throws {
        let work = Self.folder("Work", position: 0)
        let inFolder = Self.edit("Report", daysAgo: 0, in: work)
        let loose = Self.edit("Loose", daysAgo: 1)
        let (viewModel, _, observation) = try await makeViewModel(folders: [work], edits: [inFolder, loose])
        defer { observation.cancel() }

        #expect(viewModel.sections.flatMap(\.edits).map(\.id) == [loose.id])
        #expect(viewModel.folderSections.map(\.folder.id) == [work.id])
        #expect(viewModel.folderSections.first?.edits.map(\.id) == [inFolder.id])
        #expect(viewModel.folderSections.first?.isExpanded == true)
        #expect(Set(viewModel.edits.map(\.id)) == [inFolder.id, loose.id])
        #expect(!viewModel.hasNoSearchResults)
    }

    @Test func emptyFolderAloneIsNotEmptyState() async throws {
        let (viewModel, _, observation) = try await makeViewModel(folders: [Self.folder("Ideas", position: 0)], edits: [])
        defer { observation.cancel() }

        #expect(!viewModel.isEmpty)
        #expect(viewModel.folderSections.first?.totalCount == 0)
    }

    @Test func searchHidesFoldersWithoutMatchesAndExpandsTheRest() async throws {
        let work = Self.folder("Work", position: 0)
        let travel = Self.folder("Travel", position: 1)
        let (viewModel, _, observation) = try await makeViewModel(folders: [work, travel], edits: [
            Self.edit("Swift actors", daysAgo: 0, in: work),
            Self.edit("Budget", daysAgo: 0, in: work),
            Self.edit("Lisbon", daysAgo: 0, in: travel),
            Self.edit("Swift macros", daysAgo: 1),
        ])
        defer { observation.cancel() }
        viewModel.toggleExpanded(work)
        #expect(viewModel.folderSections.first?.isExpanded == false)

        viewModel.searchText = "swift"

        #expect(viewModel.folderSections.map(\.folder.id) == [work.id])
        #expect(viewModel.folderSections.first?.edits.map(\.title) == ["Swift actors"])
        #expect(viewModel.folderSections.first?.totalCount == 2)
        #expect(viewModel.folderSections.first?.isExpanded == true)
        #expect(viewModel.sections.flatMap(\.edits).map(\.title) == ["Swift macros"])

        viewModel.searchText = "nothing"
        #expect(viewModel.hasNoSearchResults)
    }

    @Test func dropMovesKnownEditIntoFolderAndBack() async throws {
        let work = Self.folder("Work", position: 0)
        let edit = Self.edit("Report", daysAgo: 0)
        let (viewModel, _, observation) = try await makeViewModel(folders: [work], edits: [edit])
        defer { observation.cancel() }
        viewModel.select(edit)
        viewModel.toggleExpanded(work)

        #expect(viewModel.dropEdits([edit.id], into: work.id))
        try await waitUntil { viewModel.folderSections.first?.edits.map(\.id) == [edit.id] }
        #expect(viewModel.sections.isEmpty)
        // Свёрнутая папка раскрывается, чтобы было видно, куда упал правка.
        #expect(viewModel.folderSections.first?.isExpanded == true)
        #expect(viewModel.selectedEditId == edit.id)

        // Повторный дроп в ту же папку — переносить нечего.
        #expect(!viewModel.dropEdits([edit.id], into: work.id))

        #expect(viewModel.dropEdits([edit.id], into: nil))
        try await waitUntil { viewModel.sections.flatMap(\.edits).map(\.id) == [edit.id] }
        #expect(viewModel.folderSections.first?.edits.isEmpty == true)
        #expect(!viewModel.actionFailed)
    }

    @Test func dropWithUnknownEditOrFolderIsIgnored() async throws {
        let work = Self.folder("Work", position: 0)
        let edit = Self.edit("Report", daysAgo: 0)
        let (viewModel, repository, observation) = try await makeViewModel(folders: [work], edits: [edit])
        defer { observation.cancel() }

        #expect(!viewModel.dropEdits([UUID()], into: work.id))
        #expect(!viewModel.dropEdits([edit.id], into: UUID()))
        #expect(!viewModel.dropEdits([], into: work.id))

        // Папку удалили, а снимок во ViewModel ещё не обновился.
        try await repository.deleteFolder(id: work.id)
        try await waitUntil { viewModel.folderSections.isEmpty }
        #expect(!viewModel.dropEdits([edit.id], into: work.id))

        // Неизвестные id в смешанном дропе отбрасываются, известные переносятся.
        let travel = Self.folder("Travel", position: 0)
        try await repository.createFolder(id: travel.id, name: travel.name, createdAt: travel.createdAt)
        try await waitUntil { viewModel.folderSections.count == 1 }
        #expect(viewModel.dropEdits([UUID(), edit.id, edit.id], into: travel.id))
        try await waitUntil { viewModel.folderSections.first?.edits.map(\.id) == [edit.id] }
        #expect(!viewModel.actionFailed)
    }

    @Test func dropRacingWithEditDeletionDoesNotAlert() async throws {
        let work = Self.folder("Work", position: 0)
        let edit = Self.edit("Report", daysAgo: 0)
        let (viewModel, repository, observation) = try await makeViewModel(folders: [work], edits: [edit])
        defer { observation.cancel() }

        // Снимок ещё содержит правка, а в хранилище его уже нет.
        try await repository.delete(id: edit.id)
        #expect(viewModel.dropEdits([edit.id], into: work.id))
        try await waitUntil { viewModel.edits.isEmpty }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!viewModel.actionFailed)
    }

    @Test func createAndRenameFolderTrimsNameAndRejectsBlank() async throws {
        let (viewModel, _, observation) = try await makeViewModel(edits: [])
        defer { observation.cancel() }

        viewModel.beginCreateFolder()
        viewModel.folderNameText = "  "
        #expect(!viewModel.canCommitFolderName)
        await viewModel.commitFolderName()?.value
        #expect(viewModel.folderNameEditing == nil)
        #expect(viewModel.folderSections.isEmpty)

        viewModel.beginCreateFolder()
        viewModel.folderNameText = " Work \n"
        await viewModel.commitFolderName()?.value
        try await waitUntil { viewModel.folderSections.map(\.folder.name) == ["Work"] }

        let folder = try #require(viewModel.folderSections.first?.folder)
        viewModel.beginRenameFolder(folder)
        #expect(viewModel.folderNameText == "Work")
        viewModel.folderNameText = "Projects"
        await viewModel.commitFolderName()?.value
        try await waitUntil { viewModel.folderSections.map(\.folder.name) == ["Projects"] }
        #expect(!viewModel.actionFailed)
    }

    @Test func deleteFolderMovesEditsToRecentsAndKeepsSelection() async throws {
        let work = Self.folder("Work", position: 0)
        let edit = Self.edit("Report", daysAgo: 0, in: work)
        let (viewModel, _, observation) = try await makeViewModel(folders: [work], edits: [edit])
        defer { observation.cancel() }
        viewModel.select(edit)

        viewModel.requestDeleteFolder(work)
        await viewModel.confirmDeleteFolder()?.value

        try await waitUntil { viewModel.folderSections.isEmpty }
        #expect(viewModel.folderPendingDeletion == nil)
        #expect(viewModel.sections.flatMap(\.edits).map(\.id) == [edit.id])
        #expect(viewModel.selectedEditId == edit.id)
        #expect(!viewModel.actionFailed)
    }

    @Test func moveFolderUpAndDownRespectsBounds() async throws {
        let a = Self.folder("A", position: 0)
        let b = Self.folder("B", position: 1)
        let c = Self.folder("C", position: 2)
        let (viewModel, _, observation) = try await makeViewModel(folders: [a, b, c], edits: [])
        defer { observation.cancel() }
        #expect(viewModel.folderSections.map(\.canMoveUp) == [false, true, true])
        #expect(viewModel.folderSections.map(\.canMoveDown) == [true, true, false])

        await viewModel.moveFolderUp(c)
        try await waitUntil { viewModel.folderSections.map(\.folder.name) == ["A", "C", "B"] }

        await viewModel.moveFolderDown(a)
        try await waitUntil { viewModel.folderSections.map(\.folder.name) == ["C", "A", "B"] }

        // За края — ничего не происходит.
        await viewModel.moveFolderUp(viewModel.folderSections[0].folder)
        await viewModel.moveFolderDown(viewModel.folderSections[2].folder)
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.folderSections.map(\.folder.name) == ["C", "A", "B"])
        #expect(!viewModel.actionFailed)
    }

    // MARK: Алерты

    /// Алерт, закрываясь, сбрасывает состояние через binding сразу после нажатия кнопки —
    /// раньше, чем начнётся запись. Подтверждение должно пережить этот сброс.
    @Test func confirmationsSurviveAlertDismissal() async throws {
        let edit = Self.edit("Old title", daysAgo: 0)
        let doomed = Self.edit("Doomed", daysAgo: 1)
        let work = Self.folder("Work", position: 0)
        let (viewModel, _, observation) = try await makeViewModel(folders: [work], edits: [edit, doomed])
        defer { observation.cancel() }

        viewModel.beginRename(edit)
        viewModel.renameText = "New title"
        let rename = viewModel.commitRename()
        viewModel.cancelRename()

        viewModel.requestDelete(doomed)
        let delete = viewModel.confirmDelete()
        viewModel.editPendingDeletion = nil

        viewModel.beginCreateFolder()
        viewModel.folderNameText = "Travel"
        let create = viewModel.commitFolderName()
        viewModel.cancelFolderNameEditing()

        viewModel.requestDeleteFolder(work)
        let deleteFolder = viewModel.confirmDeleteFolder()
        viewModel.folderPendingDeletion = nil

        for task in [rename, delete, create, deleteFolder] { await task?.value }
        try await waitUntil {
            viewModel.edits.map(\.title) == ["New title"]
                && viewModel.folderSections.map(\.folder.name) == ["Travel"]
        }
        #expect(!viewModel.actionFailed)
    }
}
