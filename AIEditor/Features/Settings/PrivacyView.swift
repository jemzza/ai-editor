import SwiftUI

/// Подэкран Privacy: где лежат правки и куда уходит текст, разрешения диктовки,
/// «Delete all history».
struct PrivacyView: View {
    @State private var viewModel: PrivacyViewModel
    private let openAppSettings: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    private static let groqPrivacyPolicy = URL(string: "https://groq.com/privacy-policy/")

    init(viewModel: PrivacyViewModel, openAppSettings: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.openAppSettings = openAppSettings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                dataSection
                dictationSection
                deleteSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.appBackground)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't delete history", isPresented: $viewModel.deleteFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.refreshPermissions() }
        }
    }

    private var dataSection: some View {
        SettingsSection("Your data") {
            InfoRow(title: "History stays on this device", systemImage: "iphone",
                    text: "Your texts, results and folders are stored only on this device. The app doesn't sync them to any server.")
            SettingsDivider()
            InfoRow(title: "Text is sent to Groq", systemImage: "paperplane",
                    text: "To paraphrase, shorten, translate or fix your text, it is sent to Groq, the AI provider. Only the text of the current edit is sent.")
            if let url = Self.groqPrivacyPolicy {
                SettingsDivider()
                Link(destination: url) {
                    SettingsRowLabel(title: "Groq Privacy Policy", systemImage: "doc.text", accessory: .external)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dictationSection: some View {
        SettingsSection("Dictation",
                        footer: "Speech is recognized on this device when your language supports it; otherwise it's sent to Apple.") {
            ForEach(viewModel.permissions) { state in
                SettingsRowLabel(title: state.permission.title, systemImage: state.permission.systemImage,
                                 value: state.status.title, accessory: .none)
                    .accessibilityElement(children: .combine)
                SettingsDivider()
            }
            Button(action: openAppSettings) {
                SettingsRowLabel(title: "Open Settings", systemImage: "gear", accessory: .external)
            }
            .buttonStyle(.plain)
        }
    }

    private var deleteSection: some View {
        SettingsSection(footer: "Deletes all edits and folders from this device. Settings are kept.") {
            Button(role: .destructive) {
                viewModel.requestDeleteAll()
            } label: {
                SettingsRowLabel(title: "Delete all history", systemImage: "trash", accessory: .none, tint: .red)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isDeleting)
            // На iPad диалог — поповер со стрелкой к этой кнопке.
            .confirmationDialog("Delete all history?", isPresented: $viewModel.isConfirmingDeleteAll,
                                titleVisibility: .visible) {
                Button("Delete All History", role: .destructive) { viewModel.confirmDeleteAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All edits and folders will be permanently deleted from this device.")
            }
        }
    }
}

/// Строка-пояснение: иконка, заголовок и текст под ним.
private struct InfoRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

extension AppPermission {
    var title: LocalizedStringKey {
        switch self {
        case .microphone: "Microphone"
        case .speechRecognition: "Speech Recognition"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone: "mic"
        case .speechRecognition: "waveform"
        }
    }
}

extension PermissionStatus {
    var title: LocalizedStringKey {
        switch self {
        case .notDetermined: "Not asked yet"
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .restricted: "Restricted"
        }
    }
}

#if DEBUG
@MainActor
private func privacyPreview() -> some View {
    let dependencies = EditorDependencies.preview()
    return NavigationStack {
        PrivacyView(viewModel: PrivacyViewModel(session: dependencies.session,
                                                permissions: dependencies.permissions),
                    openAppSettings: {})
    }
}

#Preview("Light") { privacyPreview() }
#Preview("Dark") { privacyPreview().preferredColorScheme(.dark) }
#endif
