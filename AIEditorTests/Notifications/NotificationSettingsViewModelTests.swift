import Foundation
import Testing
@testable import AIEditor

@MainActor
struct NotificationSettingsViewModelTests {
    private func make(_ status: NotificationAuthorization, grants: Bool = true,
                      settings: InMemorySettingsStore = InMemorySettingsStore())
        -> (NotificationSettingsViewModel, FakeNotificationScheduler, InMemorySettingsStore) {
        let scheduler = FakeNotificationScheduler(status: status, grantsOnRequest: grants)
        return (NotificationSettingsViewModel(settings: settings, scheduler: scheduler), scheduler, settings)
    }

    @Test func openingTheScreenDoesNotAskForPermission() async {
        let (viewModel, scheduler, _) = make(.notDetermined)

        await viewModel.refresh()

        #expect(scheduler.requestCount == 0)
        #expect(viewModel.areTogglesEnabled)
        #expect(viewModel.isOn(.editReady) == false)
    }

    @Test func firstEnableAsksOnceAndStoresTheAnswer() async {
        let (viewModel, scheduler, settings) = make(.notDetermined)
        await viewModel.refresh()

        await viewModel.setEnabled(.editReady, true)
        await viewModel.setEnabled(.editReady, false)
        await viewModel.setEnabled(.editReady, true)

        #expect(scheduler.requestCount == 1)
        #expect(settings.notifyOnEditReady)
        #expect(viewModel.isOn(.editReady))
    }

    @Test func declinedRequestKeepsToggleOffAndShowsNotice() async {
        let (viewModel, scheduler, settings) = make(.notDetermined, grants: false)
        await viewModel.refresh()

        await viewModel.setEnabled(.editReady, true)

        #expect(scheduler.requestCount == 1)
        #expect(settings.notifyOnEditReady == false)
        #expect(viewModel.isOn(.editReady) == false)
        #expect(viewModel.isDeniedInSystem)
        #expect(viewModel.areTogglesEnabled == false)
    }

    @Test func deniedInSystemShowsTogglesOffEvenIfStoredOn() async {
        let (viewModel, scheduler, settings) = make(.denied, settings: InMemorySettingsStore(notifyOnEditReady: true))
        await viewModel.refresh()

        #expect(viewModel.isOn(.editReady) == false)
        #expect(viewModel.isDeniedInSystem)

        await viewModel.setEnabled(.editReady, true)
        #expect(scheduler.requestCount == 0)

        // Разрешили в системных Настройках — сохранённое значение снова видно.
        scheduler.status = .authorized
        await viewModel.refresh()
        #expect(viewModel.isOn(.editReady))
        #expect(settings.notifyOnEditReady)
    }

    @Test func disablingNeverAsks() async {
        let (viewModel, scheduler, settings) = make(.authorized, settings: InMemorySettingsStore(notifyOnEditReady: true))
        await viewModel.refresh()

        await viewModel.setEnabled(.editReady, false)

        #expect(settings.notifyOnEditReady == false)
        #expect(scheduler.requestCount == 0)
    }
}
