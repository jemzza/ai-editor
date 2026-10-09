import Foundation

/// Сообщения для LLM по действию и исходному тексту: системная инструкция + текст пользователя.
///
/// Контракт. Реализация с промптами для каждого действия — на 4-часовом отрезке (ветка A);
/// до неё работает `StubPromptBuilder`.
/// Требования к промптам: в ответе только результат — без пояснений («Here is…»), кавычек
/// и Markdown; язык результата — язык исходника (кроме `translate`).
protocol PromptBuilding: Sendable {
    func messages(for action: EditAction, source: String) -> [LLMMessage]
}
