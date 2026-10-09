import SwiftUI

/// Диктовка в поле исходного текста. Собирает экран из `DictationViewModel`.
struct DictationControls {
    var state = DictationViewModel.State.idle
    var duration: Duration = .zero
    var level: Float = 0
    var canOpenSettings = false
    /// Палец лёг на микрофон / поднялся.
    var press: () -> Void = {}
    var release: () -> Void = {}
    /// VoiceOver: двойное касание.
    var toggle: () -> Void = {}
    var openSettings: () -> Void = {}
    var dismissMessage: () -> Void = {}
}

/// Микрофон «зажми и говори»: пока палец на кнопке — синий круг и запись;
/// хаптик на нажатие и на отпускание. С VoiceOver — обычная кнопка-переключатель.
struct DictationButton: View {
    let dictation: DictationControls

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 34
    @State private var isPressed = false
    @State private var pressCount = 0
    @State private var releaseCount = 0

    /// Запись (или подготовка к ней) — синий круг.
    private var isRecording: Bool {
        dictation.state == .recording || dictation.state == .preparing
    }

    private var isTranscribing: Bool {
        switch dictation.state {
        case .transcribing, .downloading: true
        default: false
        }
    }

    var body: some View {
        if isTranscribing {
            ProgressView()
                .frame(width: size, height: size)
                .accessibilityLabel(Text("Transcribing"))
        } else {
            microphone
        }
    }

    private var microphone: some View {
        let highlighted = isPressed || isRecording
        return Image(systemName: highlighted ? "mic.fill" : "mic")
            .font(.system(size: size * 0.5))
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: size, height: size)
            // Синий — системный цвет (не бренд): «микрофон включён», как в системных диктовках.
            .background(highlighted ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.clear), in: .circle)
            .scaleEffect(isPressed ? 1.15 : 1)
            .animation(.snappy(duration: 0.2), value: highlighted)
            .animation(.snappy(duration: 0.2), value: isPressed)
            .contentTransition(.symbolEffect(.replace))
            .contentShape(.circle)
            // `minimumDuration: .infinity` — «долгое нажатие» никогда не срабатывает, нужен только
            // момент касания и отпускания; палец может съехать с кнопки — запись не обрывается.
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity) {
            } onPressingChanged: { pressing in
                isPressed = pressing
                if pressing {
                    pressCount += 1
                    dictation.press()
                } else {
                    releaseCount += 1
                    dictation.release()
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: pressCount)
            .sensoryFeedback(.impact(weight: .light), trigger: releaseCount)
            .accessibilityElement()
            .accessibilityLabel(isRecording ? Text("Stop dictation") : Text("Dictate"))
            .accessibilityHint(Text("Hold to dictate, release to stop."))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { dictation.toggle() }
    }
}

/// Слева от кнопок: «Listening…» с уровнем громкости или прогресс загрузки модели.
struct DictationStatus: View {
    let state: DictationViewModel.State
    let duration: Duration
    let level: Float

    var body: some View {
        switch state {
        case .recording:
            Label {
                Text("Recording \(duration.formatted(.time(pattern: .minuteSecond)))")
                    .monospacedDigit()
            } icon: {
                // Уровень громкости — заливкой символа, без анимаций (дружит с Reduce Motion).
                Image(systemName: "waveform", variableValue: Double(level))
            }
            .textStyle(.caption)
            .foregroundStyle(.blue)
        case .transcribing:
            Text("Transcribing…")
                .textStyle(.caption)
                .foregroundStyle(.secondary)
        case let .downloading(fraction):
            Text("Downloading speech model… \(Int((fraction * 100).rounded()))%")
                .textStyle(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        case .idle, .preparing, .unavailable, .failed, .holdHint, .nothingHeard:
            EmptyView()
        }
    }
}

/// Почему диктовка не началась: текст, «Open Settings» (если дело в разрешении), «Dismiss».
struct DictationMessage: View {
    let presentation: DictationMessagePresentation
    let dictation: DictationControls

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: presentation.systemImage)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.title)
                    .foregroundStyle(.primary)
                if dictation.canOpenSettings {
                    Button("Open Settings", action: dictation.openSettings)
                        .foregroundStyle(.appAccent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dictation.dismissMessage)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(.rect)
        }
        .textStyle(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.appSurface, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.secondary.opacity(0.25)) }
    }
}
