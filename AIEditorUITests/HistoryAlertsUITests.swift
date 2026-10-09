import XCTest

/// Подтверждения в алертах через настоящий UI: модульные тесты зовут методы
/// ViewModel в обход алерта и не ловят, что алерт, закрываясь, сбрасывает состояние.
/// Данные — `-mockData` (репозиторий в памяти с `PreviewData`).
@MainActor
final class HistoryAlertsUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testRenameAndDeleteThroughAlerts() throws {
        let app = XCUIApplication.launchWithMockData()
        app.openSidebar()

        // Переименование: контекстное меню → алерт с полем → «Save».
        let edit = app.buttons["Their going to the libary tomorow"]
        XCTAssertTrue(edit.waitForExistence(timeout: timeout))
        app.contextMenuItem("Rename", on: edit).tap()

        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        app.replaceText(in: field, with: "Grammar check")
        app.alerts.buttons["Save"].tap()

        XCTAssertTrue(app.buttons["Grammar check"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["Their going to the libary tomorow"].exists)

        // Удаление: контекстное меню → подтверждение → правки нет.
        let doomed = app.buttons["Please find attached the updated contract"]
        XCTAssertTrue(doomed.exists)
        app.contextMenuItem("Delete", on: doomed).tap()

        let confirm = app.confirmationButton("Delete")
        XCTAssertTrue(confirm.exists)
        confirm.tap()

        XCTAssertTrue(waitForDisappearance(of: doomed, timeout: timeout))
    }
}
