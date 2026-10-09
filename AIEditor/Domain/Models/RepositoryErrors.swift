import Foundation

/// Правки нет — например, её удалили во время стриминга.
/// `EditService` глотает эту ошибку при записи результата.
struct EditNotFound: Error, Hashable, Sendable {
    let id: UUID
}

struct FolderNotFound: Error, Hashable, Sendable {
    let id: UUID
}
