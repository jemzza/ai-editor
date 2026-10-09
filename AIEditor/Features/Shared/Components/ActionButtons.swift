import SwiftUI

/// Ожидание первого токена («Загрузка» в UI): три пульсирующие точки.
struct GeneratingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var dotSize: CGFloat = 7

    var body: some View {
        HStack(spacing: dotSize * 0.6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.secondary)
                    .frame(width: dotSize, height: dotSize)
                    .phaseAnimator([0.3, 1.0], trigger: reduceMotion) { dot, phase in
                        dot.opacity(reduceMotion ? 0.6 : phase)
                    } animation: { _ in
                        .easeInOut(duration: 0.5).delay(Double(index) * 0.15)
                    }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement()
        .accessibilityLabel(Text("Generating result"))
    }
}

/// Маленькая иконка-кнопка (Copy, Read aloud, Retry) с зоной нажатия 44pt.
struct IconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 32)
            .contentShape(.rect)
    }
}

/// Круглая кнопка: главная (акцент) или нейтральная («Stop»).
struct CircleButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isEnabled = true
    /// Главная — акцентная; «Stop» — нейтральная (цвет текста).
    var isProminent = true
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 34

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: size * 0.45, weight: .bold))
            // Цвет фона экрана на акценте/`.primary` контрастен в обеих темах.
            .foregroundStyle(.appOnAccent)
            .frame(width: size, height: size)
            .background(background, in: .circle)
            .contentShape(.circle)
            .disabled(!isEnabled)
            .animation(.snappy, value: isEnabled)
    }

    private var background: AnyShapeStyle {
        guard isEnabled else { return AnyShapeStyle(.secondary.opacity(0.35)) }
        return isProminent ? AnyShapeStyle(.appAccent) : AnyShapeStyle(.primary)
    }
}

/// «Stop» во время генерации.
struct StopButton: View {
    let action: () -> Void

    var body: some View {
        CircleButton(title: "Stop", systemImage: "stop.fill", isProminent: false, action: action)
    }
}

extension View {
    /// Скрытие клавиатуры: тап по пустому месту. Свайп — `.scrollDismissesKeyboard(.interactively)`
    /// у прокрутки экрана.
    func dismissesKeyboardOnTap(_ focus: FocusState<Bool>.Binding) -> some View {
        contentShape(.rect).onTapGesture { focus.wrappedValue = false }
    }
}
