import Foundation
import Observation

/// Просьба открыть правку извне экранов — нажатие на уведомление. Пишет `AppDelegate`,
/// выполняет `RootView`. На холодном старте просьба ждёт, пока откроется база и
/// появится `RootView`.
@MainActor
@Observable
final class EditNavigationRequests {
    private(set) var pendingEditId: UUID?

    func requestOpenEdit(id: UUID) {
        pendingEditId = id
    }

    /// Забирает просьбу (один раз).
    func takePendingEditId() -> UUID? {
        defer { pendingEditId = nil }
        return pendingEditId
    }
}
