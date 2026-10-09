import Foundation

/// Кусок сравнения «было — стало». Склеенные по порядку `equal` + `removed` дают исходный
/// текст, `equal` + `inserted` — результат.
///
/// Контракт. Реализация (`WordDiffing`) — на 4-часовом отрезке.
struct DiffSegment: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case equal
        case inserted
        case removed
    }

    let kind: Kind
    let text: String
}
