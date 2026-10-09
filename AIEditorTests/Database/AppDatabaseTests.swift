import Foundation
import GRDB
import Testing
@testable import AIEditor

struct AppDatabaseTests {
    @Test func migrationCreatesSchema() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.read { db in
            #expect(try db.tableExists("folder"))
            #expect(try db.tableExists("edit"))
            let columns = Set(try db.columns(in: "edit").map(\.name))
            #expect(columns == ["id", "title", "folderId", "action", "actionOption", "sourceText", "resultText",
                                "status", "failureKind", "failureRetryAt", "createdAt", "updatedAt"])
            #expect(try db.foreignKeys(on: "edit").first?.destinationTable == "folder")
        }
    }

    @Test func migrationIsIdempotentOnDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try AppDatabase.onDisk(at: url)
        let reopened = try AppDatabase.onDisk(at: url)
        let applied = try reopened.writer.read { try AppDatabase.migrator.appliedMigrations($0) }
        #expect(applied == ["v1"])
    }

    /// Неизвестное значение в базе (например, действие из будущей версии) — ошибка чтения,
    /// а не падение: поток наблюдения просто заканчивается.
    @Test func unknownActionIsInvalidValue() throws {
        let record = EditRecord(id: UUID(), title: "T", folderId: nil, action: "summarize", actionOption: nil,
                                sourceText: "S", resultText: "", status: "done", failureKind: nil,
                                failureRetryAt: nil, createdAt: .now, updatedAt: .now)
        #expect(throws: InvalidDatabaseValue(column: "action", value: "summarize")) { try record.edit() }
        var badStatus = EditRecord(Edit(title: "T", action: .shorten, sourceText: "S", createdAt: .now))
        badStatus.status = "pending"
        #expect(throws: InvalidDatabaseValue(column: "status", value: "pending")) { try badStatus.edit() }
    }
}
