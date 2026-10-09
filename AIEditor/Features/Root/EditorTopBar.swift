import SwiftUI

/// Своя верхняя панель (одинаково выглядит на iOS 18 и 26): слева — сайдбар,
/// по центру — название правки (нажатие — переименовать) и модель, справа — новый правка.
struct EditorTopBar: View {
    /// `nil` — новый правка, ещё не сохранённый.
    let edit: Edit?
    let modelName: LocalizedStringResource
    let onToggleSidebar: () -> Void
    let onRename: (Edit) -> Void
    let onNewEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            iconButton("Show sidebar", systemImage: "sidebar.leading", action: onToggleSidebar)

            Button {
                if let edit { onRename(edit) }
            } label: {
                VStack(spacing: 2) {
                    title
                        .textStyle(.editTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(modelName)
                        .textStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // Не `.disabled`: заголовок нового правки не должен выглядеть неактивным.
            .allowsHitTesting(edit != nil)
            .accessibilityHint(Text("Rename edit"))

            iconButton("New edit", systemImage: "square.and.pencil", action: onNewEdit)
                .disabled(edit == nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // Как у системных навбаров: панель не растёт бесконечно, иначе съедает экран.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(.appBackground)
    }

    private var title: Text {
        // Название — пользовательские данные; заглушка нового правки — из каталога.
        if let edit { Text(edit.title) } else { Text("New edit") }
    }

    private func iconButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.title3)
            .foregroundStyle(.primary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }
}

#if DEBUG
private struct EditorTopBarPreview: View {
    var body: some View {
        VStack(spacing: 24) {
            EditorTopBar(edit: PreviewData.paraphrased, modelName: "Groq · gpt-oss-120b",
                       onToggleSidebar: {}, onRename: { _ in }, onNewEdit: {})
            EditorTopBar(edit: nil, modelName: "Groq · gpt-oss-120b",
                       onToggleSidebar: {}, onRename: { _ in }, onNewEdit: {})
            Spacer()
        }
        .background(.appBackground)
    }
}

#Preview("Light") { EditorTopBarPreview() }
#Preview("Dark") { EditorTopBarPreview().preferredColorScheme(.dark) }
#endif
