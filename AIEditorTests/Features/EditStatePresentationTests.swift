import Foundation
import Testing
@testable import AIEditor

struct EditStatePresentationTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func edit(_ status: EditStatus, failure: EditFailure? = nil) -> Edit {
        Edit(title: "T", action: .shorten, sourceText: "S", status: status, failure: failure, createdAt: now)
    }

    @Test func bannerOnlyForFailedAndInterrupted() {
        #expect(EditErrorPresentation.forEdit(edit(.failed, failure: EditFailure(kind: .offline))) != nil)
        #expect(EditErrorPresentation.forEdit(edit(.interrupted)) != nil)
        for status in [EditStatus.streaming, .done, .cancelled] {
            #expect(EditErrorPresentation.forEdit(edit(status)) == nil)
        }
    }

    @Test(arguments: [ErrorKind.offline, .rateLimited, .unauthorized, .forbidden, .server, .unknown])
    func everyErrorKindHasDistinctText(kind: ErrorKind) {
        let others = [ErrorKind.offline, .rateLimited, .unauthorized, .forbidden, .server, .unknown]
            .filter { $0 != kind }
            .map { String(localized: EditErrorPresentation(kind: $0).title) }
        #expect(!others.contains(String(localized: EditErrorPresentation(kind: kind).title)))
    }

    @Test func retryCountdownRoundsUpAndEnds() {
        let failure = EditFailure(kind: .rateLimited, retryAt: now.addingTimeInterval(2.2))
        #expect(EditErrorPresentation.secondsUntilRetry(failure, now: now) == 3)
        #expect(EditErrorPresentation.secondsUntilRetry(failure, now: now.addingTimeInterval(3)) == nil)
        #expect(EditErrorPresentation.secondsUntilRetry(EditFailure(kind: .offline), now: now) == nil)
    }
}
