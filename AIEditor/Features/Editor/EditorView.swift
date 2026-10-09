import SwiftUI

/// ЗАГЛУШКА экрана Editor (полная версия — ветка C, docs/plan.md, UI-референс в docs/task.md).
struct EditorView: View {
    @Bindable var viewModel: EditorViewModel
    @FocusState private var isSourceFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Mode", selection: $viewModel.mode) {
                    ForEach(EditAction.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Enter or paste your text", text: $viewModel.sourceText, axis: .vertical)
                    .lineLimit(6...12)
                    .focused($isSourceFocused)
                    .padding(12)
                    .background(.appSurface, in: .rect(cornerRadius: 14))

                HStack {
                    Spacer()
                    if viewModel.isGenerating {
                        StopButton { viewModel.stop() }
                    } else {
                        CircleButton(title: "Run", systemImage: "arrow.up", isEnabled: viewModel.canStart) {
                            isSourceFocused = false
                            Task { await viewModel.start() }
                        }
                    }
                }

                result
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(.appBackground)
        .task(id: viewModel.editId) { await viewModel.observe() }
        .alert("Couldn't start the edit", isPresented: startFailedBinding) {
            Button("OK", role: .cancel) { viewModel.dismissStartFailure() }
        }
    }

    @ViewBuilder
    private var result: some View {
        if let edit = viewModel.edit {
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.isGenerating && viewModel.resultText.isEmpty {
                    GeneratingIndicator()
                } else {
                    // Результат — данные правки, а не строка интерфейса.
                    Text(viewModel.resultText)
                        .textStyle(.body)
                        .textSelection(.enabled)
                }
                if !viewModel.resultText.isEmpty && !viewModel.isGenerating {
                    IconButton(title: "Copy", systemImage: "doc.on.doc") { viewModel.copyResult() }
                }
                if let presentation = EditErrorPresentation.forEdit(edit) {
                    ErrorBanner(presentation: presentation, failure: edit.failure) {
                        Task { await viewModel.retry() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var startFailedBinding: Binding<Bool> {
        Binding { viewModel.startFailed } set: { if !$0 { viewModel.dismissStartFailure() } }
    }
}

extension EditAction.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .paraphrase: "Paraphrase"
        case .shorten: "Shorten"
        case .translate: "Translate"
        case .fixGrammar: "Fix grammar"
        }
    }
}

#if DEBUG
#Preview("Light") {
    let dependencies = EditorDependencies.preview()
    EditorView(viewModel: EditorViewModel(editId: PreviewData.paraphrased.id,
                                          repository: dependencies.repository,
                                          session: dependencies.session))
}
#endif
