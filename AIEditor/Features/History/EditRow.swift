import SwiftUI

/// Строка правки в сайдбаре: выбор, перетаскивание в папку и контекстное меню.
/// «Move to folder» в меню дублирует перетаскивание — оно недоступно с VoiceOver
/// и Switch Control и не очевидно.
struct EditRow: View {
    let edit: Edit
    let viewModel: HistoryViewModel
    /// Правка внутри папки — с отступом.
    var isNested = false
    var onNavigate: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isSelected = edit.id == viewModel.selectedEditId
        Button {
            viewModel.select(edit)
            onNavigate()
        } label: {
            // Название правки — пользовательские данные, а не строка интерфейса.
            Text(edit.title)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, isNested ? 36 : 12)
                .padding(.trailing, 12)
                .padding(.vertical, 10)
                .background(isSelected ? AnyShapeStyle(.appSurface) : AnyShapeStyle(.clear),
                            in: .rect(cornerRadius: 10))
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .draggable(EditDragItem(editId: edit.id)) {
            Text(edit.title)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.appSurface, in: .rect(cornerRadius: 10))
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") { viewModel.beginRename(edit) }
            if !viewModel.folders.isEmpty {
                moveMenu
            }
            Button("Delete", systemImage: "trash", role: .destructive) { viewModel.requestDelete(edit) }
        }
    }

    private var moveMenu: some View {
        Menu("Move to folder", systemImage: "folder") {
            ForEach(viewModel.folders) { folder in
                let isCurrent = edit.folderId == folder.id
                Button {
                    viewModel.dropEdits([edit.id], into: folder.id)
                } label: {
                    // Имя папки — пользовательские данные.
                    if isCurrent {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
                .disabled(isCurrent)
            }
            if edit.folderId != nil {
                Divider()
                Button("Remove from folder", systemImage: "folder.badge.minus") {
                    viewModel.dropEdits([edit.id], into: nil)
                }
            }
        }
    }
}
