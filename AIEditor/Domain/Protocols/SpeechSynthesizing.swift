import Foundation

/// Что сейчас озвучивается. Одно состояние на всё приложение: новое чтение прерывает предыдущее.
enum SpeechPlayback: Hashable, Sendable {
    case idle
    case speaking(editId: UUID)

    var editId: UUID? {
        if case let .speaking(editId) = self { editId } else { nil }
    }
}

/// Озвучка результата правки («Read aloud»). Реализации: `SystemSpeechSynthesizer` (приложение)
/// и `FakeSpeechSynthesizer` (превью, тесты). Живёт в `AppContainer`, а не в экране:
/// чтение не обрывается при смене правки, и ViewModel узнаёт о нём только из `playbackUpdates()`.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    /// Текущее состояние сразу, дальше — при каждом изменении (в т.ч. когда чтение закончилось само).
    func playbackUpdates() -> AsyncStream<SpeechPlayback>

    /// Читает текст; предыдущее чтение прерывается.
    func speak(_ text: String, editId: UUID)

    func stop()
}
