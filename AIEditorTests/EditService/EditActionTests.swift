import Testing
@testable import AIEditor

struct EditActionTests {
    @Test(arguments: [
        EditAction.paraphrase(tone: nil), .paraphrase(tone: .formal), .shorten,
        .translate(language: "pt-BR"), .fixGrammar,
    ])
    func storageRoundTrip(action: EditAction) {
        #expect(EditAction(kind: action.kind, option: action.option) == action)
    }

    @Test func translateNeedsLanguage() {
        #expect(EditAction(kind: .translate, option: nil) == nil)
        #expect(EditAction(kind: .translate, option: "") == nil)
    }

    @Test func unknownToneMeansNoTone() {
        #expect(EditAction(kind: .paraphrase, option: "pirate") == .paraphrase(tone: nil))
    }

    @Test func stubDiffKeepsInvariant() {
        let segments = StubWordDiff().diff(from: "old text", to: "new text")
        #expect(segments.filter { $0.kind != .inserted }.map(\.text).joined() == "old text")
        #expect(segments.filter { $0.kind != .removed }.map(\.text).joined() == "new text")
        #expect(StubWordDiff().diff(from: "same", to: "same") == [DiffSegment(kind: .equal, text: "same")])
    }
}
