import Foundation

/// Модель и параметры запроса — в одном месте.
enum LLMConfig {
    /// Модель Groq. **Единственное место, где она задаётся**: если к проверке модель исчезнет
    /// с бесплатного тарифа, замените строку здесь (например, на `openai/gpt-oss-20b`) —
    /// больше ничего менять не нужно. Лимиты и выбор — docs/task.md, «Решения».
    static let model = "openai/gpt-oss-120b"

    /// Потолок длины результата. Перевод и перефразирование ≈ длине исходника
    /// (`EditLimits.maxSourceCharacters` ≈ 1,5–2,5K токенов).
    static let maxCompletionTokens = 2048

    /// gpt-oss — reasoning-модель: `low` ускоряет первый токен, рассуждения в ответ не попадают
    /// (`include_reasoning: false`).
    static let reasoningEffort = "low"
}
