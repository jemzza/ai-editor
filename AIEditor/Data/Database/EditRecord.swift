import Foundation
import GRDB

/// Строка таблицы `edit`. Доменная `Edit` о GRDB не знает — переводим здесь.
/// `EditAction` разложено на `action` + `actionOption`, `EditFailure` — на две колонки.
struct EditRecord: Codable, Hashable, Sendable {
    static let databaseTableName = "edit"

    var id: UUID
    var title: String
    /// `nil` — правка в «Recents».
    var folderId: UUID?
    var action: String
    var actionOption: String?
    var sourceText: String
    var resultText: String
    var status: String
    var failureKind: String?
    var failureRetryAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let folderId = Column(CodingKeys.folderId)
        static let resultText = Column(CodingKeys.resultText)
        static let status = Column(CodingKeys.status)
        static let failureKind = Column(CodingKeys.failureKind)
        static let failureRetryAt = Column(CodingKeys.failureRetryAt)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

extension EditRecord: FetchableRecord, PersistableRecord {
    // Даты — числом: текстовый формат GRDB по умолчанию режет до миллисекунд,
    // и прочитанное значение не совпало бы с записанным.
    static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSinceReferenceDate
    }

    static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSinceReferenceDate
    }
}

extension EditRecord {
    init(_ edit: Edit) {
        id = edit.id
        title = edit.title
        folderId = edit.folderId
        action = edit.action.kind.rawValue
        actionOption = edit.action.option
        sourceText = edit.sourceText
        resultText = edit.resultText
        status = edit.status.rawValue
        failureKind = edit.failure?.kind.rawValue
        failureRetryAt = edit.failure?.retryAt
        createdAt = edit.createdAt
        updatedAt = edit.updatedAt
    }

    /// - Throws: `InvalidDatabaseValue`, если в базе неизвестные действие, статус или вид ошибки.
    func edit() throws -> Edit {
        guard let kind = EditAction.Kind(rawValue: action),
              let action = EditAction(kind: kind, option: actionOption) else {
            throw InvalidDatabaseValue(column: "action", value: action)
        }
        guard let status = EditStatus(rawValue: status) else {
            throw InvalidDatabaseValue(column: "status", value: status)
        }
        var failure: EditFailure?
        if let failureKind {
            guard let kind = ErrorKind(rawValue: failureKind) else {
                throw InvalidDatabaseValue(column: "failureKind", value: failureKind)
            }
            failure = EditFailure(kind: kind, retryAt: failureRetryAt)
        }
        return Edit(id: id, title: title, folderId: folderId, action: action, sourceText: sourceText,
                    resultText: resultText, status: status, failure: failure,
                    createdAt: createdAt, updatedAt: updatedAt)
    }

    /// Правки, новые (по `updatedAt`) сверху.
    static func byLastActivity() -> QueryInterfaceRequest<EditRecord> {
        order(Columns.updatedAt.desc, Columns.createdAt.desc, Column.rowID.desc)
    }
}
