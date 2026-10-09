import Foundation

/// Что сделать с текстом. Хранится в правке (`edit.action` + `edit.actionOption`).
///
/// Контракт. Промпты для каждого действия — `PromptBuilding` (реализация на 4-часовом отрезке).
enum EditAction: Hashable, Sendable {
    /// `nil` — тон не выбран (как `standard`).
    case paraphrase(tone: ParaphraseTone?)
    case shorten
    /// - Parameter language: BCP-47 код языка результата («de», «pt-BR»).
    case translate(language: String)
    case fixGrammar

    /// Режим без параметров — для переключателя сверху экрана.
    var kind: Kind {
        switch self {
        case .paraphrase: .paraphrase
        case .shorten: .shorten
        case .translate: .translate
        case .fixGrammar: .fixGrammar
        }
    }

    enum Kind: String, CaseIterable, Hashable, Sendable {
        case paraphrase
        case shorten
        case translate
        case fixGrammar
    }
}

/// Тон перефразирования (бонус задания).
enum ParaphraseTone: String, CaseIterable, Hashable, Sendable {
    case standard
    case formal
    case casual
    case simple
}

// MARK: Хранение

extension EditAction {
    /// Параметр действия для колонки `actionOption`: тон или код языка.
    var option: String? {
        switch self {
        case let .paraphrase(tone): tone?.rawValue
        case let .translate(language): language
        case .shorten, .fixGrammar: nil
        }
    }

    /// Обратно из `(action, actionOption)`; `nil` — неизвестное действие или нет языка у перевода.
    init?(kind: Kind, option: String?) {
        switch kind {
        case .paraphrase: self = .paraphrase(tone: option.flatMap(ParaphraseTone.init(rawValue:)))
        case .shorten: self = .shorten
        case .translate:
            guard let option, !option.isEmpty else { return nil }
            self = .translate(language: option)
        case .fixGrammar: self = .fixGrammar
        }
    }
}
