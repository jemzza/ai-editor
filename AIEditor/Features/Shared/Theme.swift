import SwiftUI

// Дизайн-основа (UI-референс в docs/task.md): монохром. Цвета только из Assets.xcassets
// (у каждого есть Light и Dark) и системные; шрифты системные с Dynamic Type.

extension ShapeStyle where Self == Color {
    /// Фон экранов: белый / чёрный.
    static var appBackground: Color { Color(.background) }
    /// Поля, карточки, панель результата: светло-серый / тёмно-серый.
    static var appSurface: Color { Color(.surface) }
    /// Главная кнопка и выделение: чёрный / белый.
    static var appAccent: Color { Color(.accent) }
    /// Цвет текста на главной кнопке — противоположный акценту.
    static var appOnAccent: Color { Color(.background) }
    /// Добавленное в режиме Compare — приглушённый зелёный.
    static var diffInserted: Color { Color(.diffInserted) }
    /// Удалённое в режиме Compare — приглушённый красный (+ зачёркивание).
    static var diffRemoved: Color { Color(.diffRemoved) }
}

/// Стили текста. Всё — SF Pro с Dynamic Type.
enum TextStyle {
    /// Исходный текст и результат.
    case body
    case editTitle
    case caption

    var font: Font {
        switch self {
        case .body: .body
        case .editTitle: .headline
        case .caption: .caption
        }
    }
}

extension View {
    func textStyle(_ style: TextStyle) -> some View {
        font(style.font)
    }
}

#if DEBUG
private struct ThemeSwatches: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                swatch(.appBackground, title: "Background")
                swatch(.appSurface, title: "Surface")
                swatch(.appAccent, title: "Accent")
            }
            HStack(spacing: 12) {
                swatch(.diffInserted, title: "Inserted")
                swatch(.diffRemoved, title: "Removed")
            }
            Text("Edit title").textStyle(.editTitle)
            Text("Body text").textStyle(.body)
            Text("Caption").textStyle(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.appBackground)
    }

    private func swatch(_ color: Color, title: LocalizedStringKey) -> some View {
        VStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(color)
                .strokeBorder(.secondary.opacity(0.3))
                .frame(width: 64, height: 64)
            Text(title).textStyle(.caption)
        }
    }
}

#Preview("Light") { ThemeSwatches() }
#Preview("Dark") { ThemeSwatches().preferredColorScheme(.dark) }
#endif
