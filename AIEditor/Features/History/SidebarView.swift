import SwiftUI

/// Сайдбар: «New edit», поиск, папки, «Recents» по датам. Одна и та же вью — и в
/// выезжающей панели на iPhone, и в колонке `NavigationSplitView` на iPad.
/// Алерты переименования/удаления вешает `RootView`: они общие с верхней панелью.
struct SidebarView: View {
    @Bindable var viewModel: HistoryViewModel
    /// Вызывается после выбора правки или «New edit» — iPhone закрывает панель.
    var onNavigate: () -> Void = {}
    /// Шестерёнка внизу — настройки.
    var onOpenSettings: () -> Void = {}

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxHeight: .infinity)
                // Тап мимо поиска прячет клавиатуру. Строки правок и папок — кнопки,
                // у детей приоритет, этот жест им не мешает.
                .contentShape(.rect)
                .onTapGesture { isSearchFocused = false }
            footer
        }
        .background(.appBackground)
    }

    /// Выбор правки закрывает панель на iPhone — клавиатура поиска не должна остаться над правкой.
    private func navigate() {
        isSearchFocused = false
        onNavigate()
    }

    private var footer: some View {
        HStack {
            Button("Settings", systemImage: "gearshape", action: onOpenSettings)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var header: some View {
        VStack(spacing: 12) {
            SearchField(text: $viewModel.searchText, isFocused: $isSearchFocused)

            Button {
                viewModel.startNewEdit()
                navigate()
            } label: {
                Label("New edit", systemImage: "square.and.pencil")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.appAccent)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isEmpty {
            ContentUnavailableView {
                Label("No edits yet", systemImage: "text.badge.checkmark")
            } description: {
                Text("Your edits will appear here.")
            }
        } else if viewModel.hasNoSearchResults {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            history
        }
    }

    private var history: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !viewModel.isSearching {
                    SidebarSectionHeader(title: "Folders") {
                        Button("New folder", systemImage: "folder.badge.plus") { viewModel.beginCreateFolder() }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.appAccent)
                            .buttonStyle(.plain)
                    }
                }
                ForEach(viewModel.folderSections) { item in
                    FolderSection(item: item, viewModel: viewModel, onNavigate: navigate)
                }
                if !viewModel.isSearching || !viewModel.sections.isEmpty {
                    RecentsHeader(viewModel: viewModel)
                }
                ForEach(viewModel.sections) { section in
                    Text(section.group.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.edits) { edit in
                        EditRow(edit: edit, viewModel: viewModel, onNavigate: navigate)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Папка с её правками — один элемент `LazyVStack`: строки правок получают свою
/// идентичность внутри папки и не путаются с теми же правками, пока они были в «Recents».
private struct FolderSection: View {
    let item: FolderSectionItem
    let viewModel: HistoryViewModel
    let onNavigate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FolderRow(item: item, viewModel: viewModel)
            if item.isExpanded {
                ForEach(item.edits) { edit in
                    EditRow(edit: edit, viewModel: viewModel, isNested: true, onNavigate: onNavigate)
                }
                if item.edits.isEmpty {
                    Text("No edits yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 36)
                        .padding(.vertical, 6)
                }
            }
        }
    }
}

/// Заголовок «Recents» — он же цель перетаскивания «убрать из папки».
private struct RecentsHeader: View {
    let viewModel: HistoryViewModel
    @State private var isDropTargeted = false

    var body: some View {
        SidebarSectionHeader(title: "Recents")
            .padding(.bottom, 4)
            .dropHighlight(isDropTargeted)
            .dropDestination(for: EditDragItem.self) { items, _ in
                viewModel.dropEdits(items.map(\.editId), into: nil)
            } isTargeted: { isDropTargeted = $0 }
    }
}

private struct SearchField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .focused(isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.appSurface, in: .rect(cornerRadius: 12))
    }
}

/// Алерты переименования, подтверждения удаления и ошибки действия — общие для
/// сайдбара и верхней панели правки.
struct HistoryAlerts: ViewModifier {
    @Bindable var viewModel: HistoryViewModel

    func body(content: Content) -> some View {
        content
            .alert("Rename edit", isPresented: renameBinding) {
                TextField("Title", text: $viewModel.renameText)
                Button("Cancel", role: .cancel) { viewModel.cancelRename() }
                Button("Save") { viewModel.commitRename() }
                    .disabled(!viewModel.canCommitRename)
            }
            .confirmationDialog(
                "Delete this edit?",
                isPresented: deleteBinding,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { viewModel.confirmDelete() }
                Button("Cancel", role: .cancel) { viewModel.editPendingDeletion = nil }
            } message: {
                Text("The original text and its result will be removed.")
            }
            .alert(folderNameTitle, isPresented: folderNameBinding) {
                TextField("Name", text: $viewModel.folderNameText)
                Button("Cancel", role: .cancel) { viewModel.cancelFolderNameEditing() }
                Button(folderNameConfirmTitle) { viewModel.commitFolderName() }
                .disabled(!viewModel.canCommitFolderName)
            }
            .confirmationDialog(
                "Delete this folder?",
                isPresented: deleteFolderBinding,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { viewModel.confirmDeleteFolder() }
                Button("Cancel", role: .cancel) { viewModel.folderPendingDeletion = nil }
            } message: {
                Text("Edits in it will move to Recents.")
            }
            .alert("Something went wrong", isPresented: failureBinding) {
                Button("OK", role: .cancel) { viewModel.dismissActionFailure() }
            } message: {
                Text("Please try again.")
            }
    }

    private var renameBinding: Binding<Bool> {
        Binding { viewModel.renamingEdit != nil } set: { if !$0 { viewModel.cancelRename() } }
    }

    private var deleteBinding: Binding<Bool> {
        Binding { viewModel.editPendingDeletion != nil } set: { if !$0 { viewModel.editPendingDeletion = nil } }
    }

    private var folderNameTitle: LocalizedStringKey {
        viewModel.folderNameEditing == .create ? "New folder" : "Rename folder"
    }

    private var folderNameConfirmTitle: LocalizedStringKey {
        viewModel.folderNameEditing == .create ? "Create" : "Save"
    }

    private var folderNameBinding: Binding<Bool> {
        Binding { viewModel.folderNameEditing != nil } set: { if !$0 { viewModel.cancelFolderNameEditing() } }
    }

    private var deleteFolderBinding: Binding<Bool> {
        Binding { viewModel.folderPendingDeletion != nil } set: { if !$0 { viewModel.folderPendingDeletion = nil } }
    }

    private var failureBinding: Binding<Bool> {
        Binding { viewModel.actionFailed } set: { if !$0 { viewModel.dismissActionFailure() } }
    }
}

extension View {
    func historyAlerts(_ viewModel: HistoryViewModel) -> some View {
        modifier(HistoryAlerts(viewModel: viewModel))
    }
}

#if DEBUG
private struct SidebarPreview: View {
    @State private var viewModel: HistoryViewModel

    init(dependencies: EditorDependencies) {
        _viewModel = State(initialValue: HistoryViewModel(repository: dependencies.repository,
                                                           session: dependencies.session))
    }

    var body: some View {
        SidebarView(viewModel: viewModel)
            .historyAlerts(viewModel)
            .task { await viewModel.observe() }
    }
}

#Preview("Light") { SidebarPreview(dependencies: .preview()) }
#Preview("Dark") { SidebarPreview(dependencies: .preview()).preferredColorScheme(.dark) }
#Preview("Empty") { SidebarPreview(dependencies: .preview(repository: InMemoryEditRepository())) }
#Preview("Empty · Dark") {
    SidebarPreview(dependencies: .preview(repository: InMemoryEditRepository())).preferredColorScheme(.dark)
}
#Preview("Folders") { SidebarPreview(dependencies: .preview(repository: PreviewData.repositoryWithFolders())) }
#Preview("Folders · Dark") {
    SidebarPreview(dependencies: .preview(repository: PreviewData.repositoryWithFolders())).preferredColorScheme(.dark)
}
#endif
