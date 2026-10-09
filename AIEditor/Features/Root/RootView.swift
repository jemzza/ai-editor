import SwiftUI

/// Корневой экран. iPhone (compact) — свой выезжающий сайдбар поверх экрана правки;
/// iPad/Mac (regular) — `NavigationSplitView`. Верхняя панель своя в обоих случаях.
struct RootView: View {
    private let dependencies: EditorDependencies
    /// Нажатие на уведомление → открыть правка.
    private let navigation: EditNavigationRequests
    @State private var history: HistoryViewModel
    @State private var connectivity: ConnectivityStatus
    @State private var isSidebarOpen = false
    @State private var isSettingsPresented = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(dependencies: EditorDependencies, navigation: EditNavigationRequests = EditNavigationRequests()) {
        self.dependencies = dependencies
        self.navigation = navigation
        _history = State(initialValue: HistoryViewModel(repository: dependencies.repository,
                                                          session: dependencies.session))
        _connectivity = State(initialValue: ConnectivityStatus(monitor: dependencies.connectivity))
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                drawerLayout
            }
        }
        .historyAlerts(history)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(dependencies: dependencies)
                .presentationDetents([.large])
                .presentationSizing(.form)
        }
        .task { await history.observe() }
        .onChange(of: navigation.pendingEditId, initial: true) { _, editId in
            guard editId != nil, let editId = navigation.takePendingEditId() else { return }
            isSettingsPresented = false
            isSidebarOpen = false
            history.openEdit(id: editId)
        }
        .task { await connectivity.observe() }
    }

    private var drawerLayout: some View {
        SideDrawer(isOpen: $isSidebarOpen) {
            SidebarView(viewModel: history,
                        onNavigate: { withAnimation(.snappy) { isSidebarOpen = false } },
                        onOpenSettings: { isSettingsPresented = true })
        } content: {
            editScreen {
                withAnimation(.snappy) { isSidebarOpen.toggle() }
            }
        }
        .onChange(of: isSidebarOpen) { _, isOpen in
            if isOpen { dismissKeyboard() }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: history, onOpenSettings: { isSettingsPresented = true })
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            editScreen {
                withAnimation { columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func editScreen(onToggleSidebar: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            EditorTopBar(
                edit: history.selectedEdit,
                modelName: dependencies.modelName,
                onToggleSidebar: onToggleSidebar,
                onRename: { history.beginRename($0) },
                onNewEdit: { history.startNewEdit() }
            )
            if !connectivity.isOnline {
                OfflineBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            EditorScreenContent(editId: history.selectedEditId, dependencies: dependencies) { id in
                history.didCreateEdit(id: id)
            }
            .id(history.screenID)
                .frame(maxHeight: .infinity)
        }
        .animation(.snappy, value: connectivity.isOnline)
        .background(.appBackground)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Экран Editor. Пересоздаётся, когда пользователь выбирает другую правку
/// (`screenID`), но не когда новая правка получила id после первого запуска.
private struct EditorScreenContent: View {
    @State private var viewModel: EditorViewModel

    init(editId: UUID?, dependencies: EditorDependencies, onEditCreated: @escaping (UUID) -> Void) {
        _viewModel = State(initialValue: EditorViewModel(editId: editId,
                                                         repository: dependencies.repository,
                                                         session: dependencies.session,
                                                         onEditCreated: onEditCreated,
                                                         copyToClipboard: { UIPasteboard.general.string = $0 }))
    }

    var body: some View {
        EditorView(viewModel: viewModel)
    }
}

#if DEBUG
#Preview("Light") { RootView(dependencies: .preview()) }
#Preview("Dark") { RootView(dependencies: .preview()).preferredColorScheme(.dark) }
#Preview("iPad", traits: .landscapeLeft) {
    RootView(dependencies: .preview()).environment(\.horizontalSizeClass, .regular)
}
#endif
