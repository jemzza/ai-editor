import Foundation

/// Всё, что показывает сайдбар, одним согласованным снимком: правка не может
/// оказаться одновременно в папке и в «Recents» на время переноса.
struct SidebarSnapshot: Hashable, Sendable {
    struct Section: Identifiable, Hashable, Sendable {
        let folder: Folder
        /// Новые (по `updatedAt`) сверху.
        let edits: [Edit]

        var id: UUID { folder.id }
    }

    /// По `position`.
    var folders: [Section]
    /// Правки без папки, новые сверху.
    var recents: [Edit]

    static let empty = SidebarSnapshot(folders: [], recents: [])
}

extension SidebarSnapshot {
    /// Раскладывает правки по папкам. Правило группировки — одно на все реализации репозитория.
    /// - Parameters:
    ///   - folders: уже в порядке `position`.
    ///   - edits: уже в порядке «новые сверху»; порядок внутри секций сохраняется.
    init(folders: [Folder], edits: [Edit]) {
        let byFolder = Dictionary(grouping: edits.filter { $0.folderId != nil }) { $0.folderId }
        self.folders = folders.map { Section(folder: $0, edits: byFolder[$0.id] ?? []) }
        let known = Set(folders.map(\.id))
        // Правка со ссылкой на неизвестную папку показывается в «Recents», а не теряется.
        recents = edits.filter { edit in edit.folderId.map { !known.contains($0) } ?? true }
    }
}
