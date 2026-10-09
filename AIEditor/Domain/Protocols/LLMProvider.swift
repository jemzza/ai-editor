import Foundation

protocol LLMProvider: Sendable {
    /// Подпись сервиса и модели: «Groq · gpt-oss-120b».
    var displayName: LocalizedStringResource { get }

    /// Дельты текста по мере генерации. Ошибки — `LLMError`.
    ///
    /// Отмена `Task` потребителя прерывает запрос (через `onTermination`), а цикл
    /// `for try await` при этом просто заканчивается **без ошибки** — так ведёт себя
    /// `AsyncThrowingStream`. Отличать «Stop» от нормального конца нужно по `Task.isCancelled`.
    func streamReply(to messages: [LLMMessage]) -> AsyncThrowingStream<String, Error>
}
