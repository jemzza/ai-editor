import Foundation
import Speech
import UIKit

/// Какие реализации собрать. По умолчанию — только реальные; каждый фейк включается
/// только своим DEBUG launch-аргументом (в Release `LaunchOptions` всегда `.none`).
struct DependencyPlan: Hashable, Sendable {
    enum Storage: Hashable, Sendable {
        /// GRDB в Application Support.
        case disk
        /// `-mockData`: репозиторий в памяти с `PreviewData`.
        case previewData
    }

    enum Network: Hashable, Sendable {
        /// `NWPathMonitor`.
        case system
        /// `-mockOffline`: сети нет.
        case offline
    }

    enum Model: Hashable, Sendable {
        /// Groq с ключом из `Secrets.generated.swift`.
        case groq
        /// `-mockError <code>` (и `-mockOffline`): каждый запрос падает с этой ошибкой.
        case failing(ErrorKind)
        /// `-mockSlowStream`: медленный фейковый ответ.
        case slowStream
    }

    enum Dictation: Hashable, Sendable {
        /// `SpeechAnalyzer` (iOS 26) или `SFSpeechRecognizer` (iOS 18).
        case system
        /// `-mockDictation`: фейк без микрофона.
        case scripted
    }

    let storage: Storage
    let network: Network
    let model: Model
    let dictation: Dictation

    init(storage: Storage, network: Network, model: Model, dictation: Dictation = .system) {
        self.storage = storage
        self.network = network
        self.model = model
        self.dictation = dictation
    }

    init(options: LaunchOptions) {
        storage = options.useMockData ? .previewData : .disk
        network = options.forceOffline ? .offline : .system
        if let kind = options.mockError {
            model = .failing(kind)
        } else if options.forceOffline {
            // Без сети настоящий запрос упал бы с `offline` — фейк ведёт себя так же.
            model = .failing(.offline)
        } else {
            model = options.slowStream ? .slowStream : .groq
        }
        dictation = options.mockDictation ? .scripted : .system
    }
}

extension AppContainer {
    /// Собирает зависимости экранов и `EditService`. Асинхронно: при запуске репозиторий
    /// переводит оборванные `streaming` в `interrupted` раньше, чем на базу подпишутся экраны.
    func makeScreens() async throws -> EditorDependencies {
        let plan = DependencyPlan(options: launchOptions)
        let repository = try await makeRepository(plan.storage)
        let connectivity = makeConnectivity(plan.network)
        let provider = makeProvider(plan.model)
        let dictation = makeDictation(plan.dictation, connectivity: connectivity)
        let notifications = UserNotificationScheduler()
        let notificationService = NotificationService(
            settings: settings,
            scheduler: notifications,
            activity: UIKitAppActivity()
        )
        let service = EditService(
            repository: repository,
            provider: provider,
            // TODO(plan 1.2): заменить на реальный `PromptBuilder` после слияния ветки A.
            prompts: StubPromptBuilder(),
            backgroundTasks: UIKitBackgroundTasks(),
            eventHandler: notificationService,
            clock: ContinuousClock()
        )
        return EditorDependencies(
            repository: repository,
            session: service,
            // TODO(plan 1.2): заменить на реальный `WordDiff` после слияния ветки B.
            diff: StubWordDiff(),
            connectivity: connectivity,
            speech: SystemSpeechSynthesizer(),
            recorder: dictation.recorder,
            transcriber: dictation.transcriber,
            modelName: provider.displayName,
            settings: settings,
            notifications: notifications,
            permissions: SystemPermissionStatus(),
            openAppSettings: Self.openAppSettings
        )
    }

    private static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func makeRepository(_ storage: DependencyPlan.Storage) async throws -> any EditRepository {
        switch storage {
        case .disk:
            return try await GRDBEditRepository.launch(database: AppDatabase.onDisk())
        case .previewData:
            #if DEBUG
            let repository = PreviewData.repository()
            repository.markStreamingAsInterruptedNow()
            return repository
            #else
            return try await GRDBEditRepository.launch(database: AppDatabase.onDisk())
            #endif
        }
    }

    private func makeConnectivity(_ network: DependencyPlan.Network) -> any ConnectivityMonitoring {
        switch network {
        case .system:
            return NetworkConnectivityMonitor()
        case .offline:
            #if DEBUG
            return FakeConnectivityMonitor(isOnline: false)
            #else
            return NetworkConnectivityMonitor()
            #endif
        }
    }

    private func makeProvider(_ model: DependencyPlan.Model) -> any LLMProvider {
        switch model {
        case .groq:
            return GroqProvider(configuration: groqConfiguration)
        #if DEBUG
        case let .failing(kind):
            let retryAfter: Duration? = kind == .rateLimited ? .seconds(30) : nil
            return FakeLLMProvider(script: .fail(LLMError(kind: kind, retryAfter: retryAfter),
                                                 tokenDelay: .milliseconds(300)))
        case .slowStream:
            return FakeLLMProvider(script: .reply(Self.slowStreamReply, tokenDelay: .milliseconds(150)))
        #else
        case .failing, .slowStream:
            return GroqProvider(configuration: groqConfiguration)
        #endif
        }
    }

    private func makeDictation(
        _ dictation: DependencyPlan.Dictation,
        connectivity: any ConnectivityMonitoring
    ) -> (recorder: any VoiceRecording, transcriber: any SpeechTranscribing) {
        #if DEBUG
        if dictation == .scripted {
            return (FakeVoiceRecorder(),
                    FakeSpeechTranscriber(result: .success(Self.dictationPhrase), delay: .milliseconds(800)))
        }
        #endif
        if #available(iOS 26, *), SpeechTranscriber.isAvailable {
            return (SystemVoiceRecorder(), AnalyzerSpeechTranscriber(connectivity: connectivity))
        }
        return (SystemVoiceRecorder(), RecognizerSpeechTranscriber(connectivity: connectivity))
    }

    #if DEBUG
    /// Фраза фейковой диктовки (`-mockDictation`) — «речь» пользователя, не строка интерфейса.
    private static let dictationPhrase = "Their going to the libary tomorow to study for there exam."

    /// Результат фейка для `-mockSlowStream` (данные правки, не строка интерфейса).
    private static let slowStreamReply = """
        This result arrives slowly, token by token, so you can watch the text appear, \
        press Stop in the middle and check that the partial result is saved. \
        It is long enough to need scrolling on a small phone in landscape orientation.
        """
    #endif
}
