import Foundation

/// ЗАГЛУШКА до реализации `WordDiffing` (ветка B, docs/plan.md): весь исходник — удалён,
/// весь результат — добавлен. Инвариант `DiffSegment` соблюдается, поэтому экран Compare
/// можно делать и тестировать до готового алгоритма.
struct StubWordDiff: WordDiffing {
    func diff(from old: String, to new: String) -> [DiffSegment] {
        if old == new { return old.isEmpty ? [] : [DiffSegment(kind: .equal, text: old)] }
        var segments: [DiffSegment] = []
        if !old.isEmpty { segments.append(DiffSegment(kind: .removed, text: old)) }
        if !new.isEmpty { segments.append(DiffSegment(kind: .inserted, text: new)) }
        return segments
    }
}
