import SwiftUI

@main
struct AIEditorApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var container = AppContainer(
        environment: AppContainer.environment(for: .processInfo),
        launchOptions: LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
    )

    var body: some Scene {
        WindowGroup {
            switch container.environment {
            case .live:
                LiveRoot(container: container, navigation: appDelegate.navigation)
                    .windowAppearance(container.settings.appearance)
            case .unitTests:
                EmptyView()
            }
        }
    }
}

/// Запуск: открываем базу (асинхронно), потом показываем экраны.
/// `EditService` держат зависимости экранов (`session`) — он живёт столько же, сколько окно.
private struct LiveRoot: View {
    let container: AppContainer
    let navigation: EditNavigationRequests

    private enum Phase {
        case loading
        case ready(EditorDependencies)
        case failed
    }

    @State private var phase = Phase.loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                Color.appBackground.ignoresSafeArea()
            case let .ready(dependencies):
                RootView(dependencies: dependencies, navigation: navigation)
            case .failed:
                ContentUnavailableView {
                    Label("Couldn't open edit history", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Please restart the app.")
                }
                .background(.appBackground)
            }
        }
        .task {
            guard case .loading = phase else { return }
            do {
                phase = .ready(try await container.makeScreens())
            } catch {
                phase = .failed
            }
        }
    }
}
