#if DEBUG
import Foundation

extension EditorDependencies {
    /// Зависимости для превью: настоящий `EditService` поверх фейков из `Mocks/`.
    static func preview(
        repository: any EditRepository = PreviewData.repository(),
        provider: any LLMProvider = FakeLLMProvider(script: .reply(PreviewText.reply, tokenDelay: .milliseconds(60))),
        connectivity: any ConnectivityMonitoring = FakeConnectivityMonitor(isOnline: true),
        settings: any SettingsStoring = InMemorySettingsStore(),
        notifications: any LocalNotificationScheduling = FakeNotificationScheduler(status: .authorized),
        permissions: any PermissionStatusProviding = FakePermissionStatus()
    ) -> EditorDependencies {
        EditorDependencies(
            repository: repository,
            session: EditService(repository: repository, provider: provider, prompts: StubPromptBuilder(),
                                 clock: ContinuousClock()),
            diff: StubWordDiff(),
            connectivity: connectivity,
            speech: FakeSpeechSynthesizer(),
            recorder: FakeVoiceRecorder(),
            transcriber: FakeSpeechTranscriber(),
            modelName: "Groq · gpt-oss-120b",
            settings: settings,
            notifications: notifications,
            permissions: permissions,
            openAppSettings: {}
        )
    }
}

/// Тексты фейков (данные правки, не строки интерфейса).
enum PreviewText {
    static let reply = """
        This is a mock result streamed token by token. It is long enough to wrap onto several \
        lines, so you can watch the text appear smoothly and try Stop in the middle.
        """
}
#endif
