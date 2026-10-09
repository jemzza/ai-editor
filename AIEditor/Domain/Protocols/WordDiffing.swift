import Foundation

/// Сравнение «было — стало» по словам.
///
/// Контракт. Реализация — на 4-часовом отрезке (ветка B): `CollectionDifference` по токенам
/// «слово / пробелы / пунктуация», без зависимостей; до неё работает `StubWordDiff`.
protocol WordDiffing: Sendable {
    /// Сегменты по порядку текста; см. инвариант в `DiffSegment`.
    func diff(from old: String, to new: String) -> [DiffSegment]
}
