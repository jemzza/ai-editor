import Foundation

/// События `EditService`, на которые реагируют уведомления. Протокол — чтобы сервис
/// не зависел от UserNotifications. Метод `async`: сервис ждёт обработку, пока у него
/// ещё есть фоновое время (`beginBackgroundTask`).
@MainActor
protocol EditEventHandling: AnyObject {
    /// Правка дописана до конца (`done`, непустой результат).
    func editDidFinish(editId: UUID, title: String, resultText: String) async
}
