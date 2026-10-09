import Testing
@testable import AIEditor

struct EditTitleTests {
    @Test func shortTextIsKeptWithCollapsedWhitespace() {
        #expect(EditTitle.make(from: "  Fix   this\nplease ") == "Fix this please")
    }

    @Test func longTextIsCutAtWordBoundary() {
        let title = EditTitle.make(from: "The meeting has been moved to Thursday because half the team is out")
        #expect(title == "The meeting has been moved to Thursday…")
        #expect(title.count <= EditTitle.maxLength)
    }

    @Test func longSingleWordIsCutHard() {
        let title = EditTitle.make(from: String(repeating: "a", count: 100))
        #expect(title.count == EditTitle.maxLength)
        #expect(title.hasSuffix("…"))
    }

    @Test func emptyTextGetsPlaceholder() {
        #expect(EditTitle.make(from: " \n ") == String(localized: "Untitled"))
    }
}
