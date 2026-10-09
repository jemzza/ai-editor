import Foundation
import Testing
@testable import AIEditor

/// Процесс умер посреди стрима — при следующем запуске правка `interrupted`.
@Suite("Launch recovery")
struct LaunchRecoveryTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func streamingEditsBecomeInterruptedOnRelaunch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("AIEditor.sqlite")

        let streaming = Edit(title: "Half", action: .shorten, sourceText: "Source", resultText: "Half a res",
                             status: .streaming, createdAt: t0)
        let done = Edit(title: "Done", action: .fixGrammar, sourceText: "Source", resultText: "Done",
                        status: .done, createdAt: t0.addingTimeInterval(1))

        // Первый «запуск»: правка осталась в `streaming`, процесс завершился.
        do {
            let repository = GRDBEditRepository(database: try AppDatabase.onDisk(at: url))
            try await repository.insert(streaming)
            try await repository.insert(done)
        }

        // Второй запуск — та же база с диска.
        let repository = try await GRDBEditRepository.launch(database: try AppDatabase.onDisk(at: url))

        let recovered = try #require(try await firstValue(of: repository.observeEdit(id: streaming.id)))
        #expect(recovered.status == .interrupted)
        #expect(recovered.resultText == "Half a res")
        #expect(recovered.status.isRetryable)
        #expect(try await firstValue(of: repository.observeEdit(id: done.id))?.status == .done)
    }

    @Test func launchWithoutStreamingChangesNothing() async throws {
        let database = try AppDatabase.inMemory()
        let edit = Edit(title: "Done", action: .shorten, sourceText: "Source", resultText: "S",
                        status: .done, createdAt: t0)
        try await GRDBEditRepository(database: database).insert(edit)

        let repository = try await GRDBEditRepository.launch(database: database)

        #expect(try await firstValue(of: repository.observeEdit(id: edit.id)) == edit)
    }
}
