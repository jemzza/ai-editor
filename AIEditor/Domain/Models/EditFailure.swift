import Foundation

enum ErrorKind: String, Hashable, Sendable {
    /// Нет сети.
    case offline
    /// 429 — кончился лимит API.
    case rateLimited
    /// 401 или ключ отсутствует.
    case unauthorized
    /// 403 — например, регион не поддерживается.
    case forbidden
    /// 5xx.
    case server
    case unknown
}

/// Причина ошибки правки. Хранится вместе с правкой, чтобы
/// «Try again in N s» оставалась верной и после перезапуска.
struct EditFailure: Hashable, Sendable {
    let kind: ErrorKind
    /// Когда можно повторить (из `retry-after` при 429).
    let retryAt: Date?

    init(kind: ErrorKind, retryAt: Date? = nil) {
        self.kind = kind
        self.retryAt = retryAt
    }
}
