import Foundation

/// ЗАГЛУШКА до реализации `PromptBuilding` (ветка A, docs/plan.md): одна общая инструкция,
/// чтобы путь «кнопка → Groq → база → экран» работал целиком уже в шаблоне.
struct StubPromptBuilder: PromptBuilding {
    func messages(for action: EditAction, source: String) -> [LLMMessage] {
        [
            LLMMessage(role: .system, content: "Rewrite the user's text. Reply with the rewritten text only."),
            LLMMessage(role: .user, content: source),
        ]
    }
}
