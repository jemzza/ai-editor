import Foundation
import GRDB

/// База приложения: соединение GRDB + схема (миграции).
/// Только Data-слой знает о GRDB; наружу база видна через `EditRepository`.
struct AppDatabase: Sendable {
    let writer: any DatabaseWriter

    /// Применяет миграции к переданному соединению.
    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Файл в Application Support. `DatabasePool` — чтения не ждут запись стрима.
    static func onDisk(fileName: String = "AIEditor.sqlite") throws -> AppDatabase {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try onDisk(at: folder.appendingPathComponent(fileName, isDirectory: false))
    }

    static func onDisk(at url: URL) throws -> AppDatabase {
        try AppDatabase(DatabasePool(path: url.path, configuration: makeConfiguration()))
    }

    /// Для тестов и превью: каждая база — отдельная, живёт, пока жив объект.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: makeConfiguration()))
    }

    private static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        // По умолчанию так и есть, но возврат правок удалённой папки в «Recents» держится именно на этом.
        configuration.foreignKeysEnabled = true
        return configuration
    }

    // MARK: Миграции

    /// Схема. Опубликованные миграции не меняются — только новые `registerMigration`.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // Папки одного уровня с ручным порядком.
            try db.create(table: FolderRecord.databaseTableName) { t in
                t.primaryKey("id", .blob)
                t.column("name", .text).notNull()
                t.column("position", .integer).notNull().indexed()
                t.column("createdAt", .double).notNull()
            }

            // Таблица с UUID-ключом сохраняет rowid — он задаёт порядок вставки.
            try db.create(table: EditRecord.databaseTableName) { t in
                t.primaryKey("id", .blob)
                t.column("title", .text).notNull()
                // Правка — максимум в одной папке. Удаление папки возвращает правки в «Recents».
                t.column("folderId", .blob)
                    .references(FolderRecord.databaseTableName, onDelete: .setNull)
                    .indexed()
                t.column("action", .text).notNull()
                t.column("actionOption", .text)
                t.column("sourceText", .text).notNull()
                t.column("resultText", .text).notNull()
                t.column("status", .text).notNull().indexed()
                t.column("failureKind", .text)
                t.column("failureRetryAt", .double)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull().indexed()
            }
        }
        return migrator
    }
}

/// В базе лежит значение, которого нет в доменном перечислении.
struct InvalidDatabaseValue: Error, Hashable, Sendable {
    let column: String
    let value: String
}
