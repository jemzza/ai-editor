import Foundation
import Observation

/// Группа «Recents» по дате последнего изменения правки.
enum EditDateGroup: CaseIterable, Hashable, Sendable {
    case today
    case yesterday
    case previous7Days
    case older

    var title: LocalizedStringResource {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .previous7Days: "Previous 7 days"
        case .older: "Older"
        }
    }

    static func group(for date: Date, now: Date, calendar: Calendar) -> EditDateGroup {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch days {
        case ...0: return .today
        case 1: return .yesterday
        case 2...7: return .previous7Days
        default: return .older
        }
    }
}

struct EditSection: Identifiable, Hashable, Sendable {
    let group: EditDateGroup
    let edits: [Edit]

    var id: EditDateGroup { group }
}

/// Папка в сайдбаре с правками, которые сейчас видны (с учётом поиска).
struct FolderSectionItem: Identifiable, Hashable, Sendable {
    let folder: Folder
    let edits: [Edit]
    /// Сколько правок в папке всего, без учёта поиска.
    let totalCount: Int
    let isExpanded: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool

    var id: UUID { folder.id }
}

/// Какое имя папки сейчас редактируют (алерт с полем ввода).
enum FolderNameEditing: Hashable, Sendable {
    case create
    case rename(Folder)
}

/// Сайдбар: папки и правки из репозитория, поиск, выбор, переименование, удаление,
/// перенос правок между папками.
/// Выбранный правка (`nil` — «New edit», черновик) хранится здесь же: его читают
/// и сайдбар, и верхняя панель правки.
@MainActor
@Observable
final class HistoryViewModel {
    /// Все правки — и в папках, и в «Recents», новые сверху.
    private(set) var edits: [Edit] = []
    private(set) var snapshot = SidebarSnapshot.empty
    /// Свёрнутые папки. Только в памяти: после перезапуска все развёрнуты.
    private(set) var collapsedFolderIds: Set<UUID> = []
    /// Пока не пришло первое значение из базы, пустое состояние не показываем.
    private(set) var hasLoaded = false
    var searchText = ""
    private(set) var selectedEditId: UUID? {
        didSet { if !isAdoptingCreatedEdit { screenID = UUID() } }
    }
    /// Идентичность экрана правки: меняется при выборе другого правки, но не когда
    /// новая правка получила id после первого запуска действия — экран не пересоздаётся.
    private(set) var screenID = UUID()
    @ObservationIgnored private var isAdoptingCreatedEdit = false

    /// Правка, который сейчас переименовывают (алерт с полем ввода).
    private(set) var renamingEdit: Edit?
    var renameText = ""
    /// Правка, удаление которого ждёт подтверждения.
    var editPendingDeletion: Edit?
    private(set) var folderNameEditing: FolderNameEditing?
    var folderNameText = ""
    /// Папка, удаление которой ждёт подтверждения.
    var folderPendingDeletion: Folder?
    private(set) var actionFailed = false

    @ObservationIgnored private let repository: any EditRepository
    @ObservationIgnored private let session: any EditSession
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    init(
        repository: any EditRepository,
        session: any EditSession,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.session = session
        self.now = now
        self.calendar = calendar
    }

    var selectedEdit: Edit? {
        selectedEditId.flatMap { id in edits.first { $0.id == id } }
    }

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !query.isEmpty }

    private func matchesSearch(_ edit: Edit) -> Bool {
        query.isEmpty || edit.title.localizedStandardContains(query) || edit.sourceText.localizedStandardContains(query)
    }

    /// Правки без папки («Recents»), подходящие под поиск, сгруппированные по дате;
    /// пустые группы опущены.
    var sections: [EditSection] {
        let visible = snapshot.recents.filter(matchesSearch)
        let date = now()
        let grouped = Dictionary(grouping: visible) {
            EditDateGroup.group(for: $0.updatedAt, now: date, calendar: calendar)
        }
        return EditDateGroup.allCases.compactMap { group in
            grouped[group].map { EditSection(group: group, edits: $0) }
        }
    }

    /// Папки по порядку. При поиске — только папки с совпадениями, развёрнутые.
    var folderSections: [FolderSectionItem] {
        let folders = snapshot.folders
        return folders.enumerated().compactMap { index, section in
            let visible = section.edits.filter(matchesSearch)
            if isSearching && visible.isEmpty { return nil }
            return FolderSectionItem(
                folder: section.folder,
                edits: visible,
                totalCount: section.edits.count,
                isExpanded: isSearching || !collapsedFolderIds.contains(section.folder.id),
                canMoveUp: index > 0,
                canMoveDown: index < folders.count - 1
            )
        }
    }

    /// Папки, в которые можно перенести правка из меню «Move to folder».
    var folders: [Folder] { snapshot.folders.map(\.folder) }

    var isEmpty: Bool { hasLoaded && edits.isEmpty && snapshot.folders.isEmpty }
    var hasNoSearchResults: Bool { isSearching && sections.isEmpty && folderSections.isEmpty }

    /// Подписка на базу; живёт, пока жива задача вызывающего (`.task` во View).
    func observe() async {
        for await snapshot in repository.observeSidebar() {
            let wasListed = selectedEditId.map { id in self.edits.contains { $0.id == id } } ?? false
            let edits = (snapshot.folders.flatMap(\.edits) + snapshot.recents)
                .sorted { ($0.updatedAt, $0.createdAt) > ($1.updatedAt, $1.createdAt) }
            self.snapshot = snapshot
            self.edits = edits
            collapsedFolderIds.formIntersection(snapshot.folders.map(\.folder.id))
            hasLoaded = true
            // Сбрасываем выбор, только если правка был в списке и исчез (удалён). Только что
            // созданный правка может ещё не дойти до списка — его не трогаем.
            if wasListed, let selectedEditId, !edits.contains(where: { $0.id == selectedEditId }) {
                self.selectedEditId = nil
            }
        }
    }

    func startNewEdit() {
        if selectedEditId != nil { selectedEditId = nil }
        searchText = ""
    }

    /// Нажатие на уведомление. Правка, которого уже нет в загруженном списке (удалён), не открываем.
    func openEdit(id: UUID) {
        if hasLoaded, !edits.contains(where: { $0.id == id }) { return }
        searchText = ""
        if selectedEditId != id { selectedEditId = id }
    }

    func select(_ edit: Edit) {
        if selectedEditId != edit.id { selectedEditId = edit.id }
    }

    /// Новая правка сохранена при первом запуске действия — выделяем её в списке.
    func didCreateEdit(id: UUID) {
        isAdoptingCreatedEdit = true
        selectedEditId = id
        isAdoptingCreatedEdit = false
    }

    // MARK: Переименование

    func beginRename(_ edit: Edit) {
        renamingEdit = edit
        renameText = edit.title
    }

    func cancelRename() {
        renamingEdit = nil
    }

    var canCommitRename: Bool {
        !renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Подтверждения из алертов (`commitRename`, `confirmDelete`, `commitFolderName`,
    // `confirmDeleteFolder`) синхронны: алерт, закрываясь, сразу сбрасывает состояние
    // через binding (`cancelRename` и т. п.), поэтому введённое забираем до записи,
    // а сама запись идёт в возвращаемой задаче (её ждут тесты).

    @discardableResult
    func commitRename() -> Task<Void, Never>? {
        guard let edit = renamingEdit else { return nil }
        renamingEdit = nil
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != edit.title else { return nil }
        return Task {
            do {
                try await repository.rename(id: edit.id, title: title)
            } catch {
                actionFailed = true
            }
        }
    }

    // MARK: Удаление

    func requestDelete(_ edit: Edit) {
        editPendingDeletion = edit
    }

    @discardableResult
    func confirmDelete() -> Task<Void, Never>? {
        guard let edit = editPendingDeletion else { return nil }
        editPendingDeletion = nil
        if selectedEditId == edit.id { selectedEditId = nil }
        return Task {
            do {
                try await session.delete(id: edit.id)
            } catch {
                actionFailed = true
            }
        }
    }

    // MARK: Перенос правок

    /// Перенос правок в папку (`nil` — в «Recents»): перетаскивание и «Move to folder».
    /// Синхронный — `.dropDestination` ждёт ответ сразу. Неизвестные id и уже лежащие
    /// в этой папке правки отбрасываются; неизвестная (удалённая) папка — дроп не принят.
    /// - Returns: `false`, если переносить нечего.
    @discardableResult
    func dropEdits(_ ids: [UUID], into folderId: UUID?) -> Bool {
        if let folderId, !snapshot.folders.contains(where: { $0.folder.id == folderId }) { return false }
        let known = Dictionary(edits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        let toMove = ids.filter { id in
            guard let edit = known[id], edit.folderId != folderId else { return false }
            return seen.insert(id).inserted
        }
        guard !toMove.isEmpty else { return false }
        // Показываем, куда упал правка.
        if let folderId { collapsedFolderIds.remove(folderId) }
        Task {
            for id in toMove {
                do {
                    try await repository.move(id: id, toFolder: folderId)
                } catch is EditNotFound {
                    // Правка удалили между дропом и записью — переносить нечего.
                } catch is FolderNotFound {
                    return
                } catch {
                    actionFailed = true
                    return
                }
            }
        }
        return true
    }

    // MARK: Папки

    func toggleExpanded(_ folder: Folder) {
        if collapsedFolderIds.contains(folder.id) {
            collapsedFolderIds.remove(folder.id)
        } else {
            collapsedFolderIds.insert(folder.id)
        }
    }

    func beginCreateFolder() {
        folderNameEditing = .create
        folderNameText = ""
    }

    func beginRenameFolder(_ folder: Folder) {
        folderNameEditing = .rename(folder)
        folderNameText = folder.name
    }

    func cancelFolderNameEditing() {
        folderNameEditing = nil
    }

    var canCommitFolderName: Bool {
        !folderNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func commitFolderName() -> Task<Void, Never>? {
        guard let editing = folderNameEditing else { return nil }
        folderNameEditing = nil
        let name = folderNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if case .rename(let folder) = editing, name == folder.name { return nil }
        let createdAt = now()
        return Task {
            do {
                switch editing {
                case .create:
                    try await repository.createFolder(id: UUID(), name: name, createdAt: createdAt)
                case .rename(let folder):
                    try await repository.renameFolder(id: folder.id, name: name)
                }
            } catch is FolderNotFound {
                // Папку удалили, пока шло переименование.
            } catch {
                actionFailed = true
            }
        }
    }

    func requestDeleteFolder(_ folder: Folder) {
        folderPendingDeletion = folder
    }

    /// Удаляет папку; её правки возвращаются в «Recents», выбор правки не меняется.
    @discardableResult
    func confirmDeleteFolder() -> Task<Void, Never>? {
        guard let folder = folderPendingDeletion else { return nil }
        folderPendingDeletion = nil
        return Task {
            do {
                try await repository.deleteFolder(id: folder.id)
            } catch {
                actionFailed = true
            }
        }
    }

    func moveFolderUp(_ folder: Folder) async { await moveFolder(folder, by: -1) }
    func moveFolderDown(_ folder: Folder) async { await moveFolder(folder, by: 1) }

    private func moveFolder(_ folder: Folder, by offset: Int) async {
        guard let index = snapshot.folders.firstIndex(where: { $0.folder.id == folder.id }) else { return }
        let target = index + offset
        guard snapshot.folders.indices.contains(target) else { return }
        do {
            try await repository.moveFolder(id: folder.id, to: target)
        } catch is FolderNotFound {
            // Папку уже удалили.
        } catch {
            actionFailed = true
        }
    }

    func dismissActionFailure() {
        actionFailed = false
    }
}
