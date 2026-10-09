import Foundation
import Testing
@testable import AIEditor

@MainActor
final class FakeAppActivity: AppActivityProviding {
    var isAppActive: Bool

    init(isAppActive: Bool) {
        self.isAppActive = isAppActive
    }
}

@MainActor
struct NotificationServiceTests {
    private func make(
        enabled: Bool = true,
        active: Bool = false,
        authorization: NotificationAuthorization = .authorized
    ) -> (NotificationService, FakeNotificationScheduler) {
        let scheduler = FakeNotificationScheduler(status: authorization)
        let service = NotificationService(settings: InMemorySettingsStore(notifyOnEditReady: enabled),
                                          scheduler: scheduler,
                                          activity: FakeAppActivity(isAppActive: active))
        return (service, scheduler)
    }

    @Test func notifiesInBackgroundWithTitleAndPreview() async {
        let (service, scheduler) = make()
        let id = UUID()

        await service.editDidFinish(editId: id, title: "Meeting note", resultText: "The meeting\nis moved.")

        #expect(scheduler.scheduled == [LocalNotification(title: "Meeting note", body: "The meeting is moved.", editId: id)])
    }

    @Test(arguments: [(false, false, NotificationAuthorization.authorized),
                      (true, true, .authorized),
                      (true, false, .denied),
                      (true, false, .notDetermined)])
    func staysSilent(enabled: Bool, active: Bool, authorization: NotificationAuthorization) async {
        let (service, scheduler) = make(enabled: enabled, active: active, authorization: authorization)

        await service.editDidFinish(editId: UUID(), title: "T", resultText: "R")

        #expect(scheduler.scheduled.isEmpty)
    }

    @Test func previewIsOneLineAndCut() {
        let long = String(repeating: "word ", count: 100)
        let preview = NotificationService.preview(long)
        #expect(preview.count <= NotificationService.previewLength)
        #expect(preview.hasSuffix("…"))
        #expect(!preview.contains("\n"))
    }
}
