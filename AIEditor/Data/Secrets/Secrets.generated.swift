// ЗАГЛУШКА без ключа: настоящий файл генерирует scripts/gen_secrets.py
// (GROQ_API_KEY=… python3 scripts/gen_secrets.py). Пока ключа нет, запросы падают как 401.

enum Secrets {
    private static let salt: [UInt8] = []

    private static let mixed: [UInt8] = []

    static var groqAPIKey: String {
        String(decoding: zip(mixed, salt).map { $0 ^ $1 }, as: UTF8.self)
    }
}
