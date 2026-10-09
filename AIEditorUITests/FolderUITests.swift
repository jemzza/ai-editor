import XCTest

/// Папки через настоящий UI : создание, «Move to folder», перетаскивание,
/// сворачивание, удаление папки с правками. Проверяет и то, что читает VoiceOver
/// у строки папки: «имя, N edits» и состояние Expanded/Collapsed.
@MainActor
final class FolderUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testFolderLifecycle() throws {
        let app = XCUIApplication.launchWithMockData()
        app.openSidebar()

        // Создание папки через алерт.
        app.buttons["New folder"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        app.replaceText(in: field, with: "Work")
        app.alerts.buttons["Create"].tap()

        let emptyFolder = app.element(labeled: "Work, 0 edits")
        XCTAssertTrue(emptyFolder.waitForExistence(timeout: timeout))
        XCTAssertEqual(emptyFolder.value as? String, "Expanded")

        // Перенос через контекстное меню (путь для VoiceOver и Switch Control).
        let report = app.buttons["Could you send me the report by Friday?"]
        app.contextMenuItem("Move to folder", on: report).tap()
        app.buttons["Work"].tap()
        let oneEdit = app.element(labeled: "Work, 1 edit")
        XCTAssertTrue(oneEdit.waitForExistence(timeout: timeout), "Move to folder")

        // Перенос перетаскиванием.
        let contract = app.buttons["Please find attached the updated contract"]
        // Короткое нажатие (длинное открывает контекстное меню), медленно и с задержкой
        // над целью: мгновенный перенос система не считает дропом.
        contract.waitUntilSettled()
        oneEdit.waitUntilSettled()
        let start = contract.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = oneEdit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.6, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.0)
        let twoEdits = app.element(labeled: "Work, 2 edits")
        XCTAssertTrue(twoEdits.waitForExistence(timeout: timeout), "Drag and drop")

        // Сворачивание: правки папки скрыты, VoiceOver слышит Collapsed.
        twoEdits.tap()
        XCTAssertTrue(waitForDisappearance(of: report, timeout: timeout))
        XCTAssertEqual(twoEdits.value as? String, "Collapsed")
        twoEdits.tap()
        XCTAssertTrue(report.waitForExistence(timeout: timeout))

        // Удаление папки с правками: папки нет, правки вернулись в «Recents».
        app.contextMenuItem("Delete", on: twoEdits).tap()
        let confirm = app.confirmationButton("Delete")
        XCTAssertTrue(confirm.exists)
        confirm.tap()

        XCTAssertTrue(waitForDisappearance(of: twoEdits, timeout: timeout))
        XCTAssertTrue(app.buttons["Could you send me the report by Friday?"].exists)
        XCTAssertTrue(app.buttons["Please find attached the updated contract"].exists)
    }
}
