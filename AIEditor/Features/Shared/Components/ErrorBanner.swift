import SwiftUI

/// Спокойная плашка ошибки: иконка, понятный текст, «Retry».
/// При 429 с `retry-after` — обратный отсчёт, «Retry» неактивна до его конца.
struct ErrorBanner: View {
    let presentation: EditErrorPresentation
    let failure: EditFailure?
    var canRetry = true
    let retry: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = EditErrorPresentation.secondsUntilRetry(failure, now: context.date)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    message(wait: wait)
                    Spacer(minLength: 0)
                    retryButton(wait: wait)
                }
                VStack(alignment: .leading, spacing: 10) {
                    message(wait: wait)
                    retryButton(wait: wait)
                }
            }
        }
        // Во вертикальной раскладке (узкий экран, крупный шрифт) плашка всё равно на всю ширину.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.appSurface, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.secondary.opacity(0.2)) }
    }

    private func message(wait: Int?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: presentation.systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let wait {
                    Text("Try again in \(wait) s")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func retryButton(wait: Int?) -> some View {
        Button("Retry", action: retry)
            .font(.subheadline.weight(.medium))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.appAccent)
            .disabled(!canRetry || wait != nil)
    }
}

#if DEBUG
#Preview("Errors") {
    VStack(spacing: 12) {
        ErrorBanner(presentation: EditErrorPresentation(kind: .offline), failure: nil) {}
        ErrorBanner(presentation: EditErrorPresentation(kind: .rateLimited),
                    failure: EditFailure(kind: .rateLimited, retryAt: .now.addingTimeInterval(30))) {}
        ErrorBanner(presentation: .interrupted, failure: nil) {}
    }
    .padding()
    .background(.appBackground)
}
#endif
