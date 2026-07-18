import SwiftUI
#if canImport(FoundationModels) && compiler(>=6.4)
import FoundationModels
#endif

struct MacSettingsView: View {
    @AppStorage(MeetingNotesService.privateCloudComputePreferenceKey)
    private var privateCloudComputeEnabled = true
    @State private var vocabulary = TranscriptionVocabulary.terms.joined(separator: "\n")

    var body: some View {
        Form {
            Section("Names and companies") {
                TextEditor(text: $vocabulary)
                    .frame(minHeight: 160)
                    .onChange(of: vocabulary) { _, value in
                        TranscriptionVocabulary.updateIfChanged(value.components(separatedBy: .newlines))
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .transcriptionVocabularyDidChange)) { _ in
                        let syncedText = TranscriptionVocabulary.terms.joined(separator: "\n")
                        if vocabulary != syncedText {
                            vocabulary = syncedText
                        }
                    }
                Text("One name or company per line. Synced with iCloud and used by Apple Speech and WhisperKit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Models") {
                LabeledContent("Automatic", value: "Apple Speech")
                LabeledContent("Euskara / multilingual", value: "Whisper Large v3 (626 MB)")
            }
            Section("Private Cloud Compute") {
                Toggle("Enhanced meeting notes", isOn: $privateCloudComputeEnabled)
                Text("Processes transcript text with Apple's private 32K-context model. Data isn't stored by Apple, and TransLocalAI falls back to the on-device model automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if privateCloudComputeEnabled {
                    MacPrivateCloudComputeStatusView()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 500)
    }
}

private struct MacPrivateCloudComputeStatusView: View {
    var body: some View {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(macOS 27, *) {
            MacPrivateCloudComputeAvailabilityView()
        } else {
            Label("Requires macOS 27 or later", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
        #else
        Label("Requires macOS 27 or later", systemImage: "info.circle")
            .foregroundStyle(.secondary)
        #endif
    }
}

#if canImport(FoundationModels) && compiler(>=6.4)
@available(macOS 27, *)
private struct MacPrivateCloudComputeAvailabilityView: View {
    private let model = PrivateCloudComputeLanguageModel()

    var body: some View {
        switch model.availability {
        case .available where model.quotaUsage.isLimitReached:
            Label("Daily limit reached — using on-device model", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        case .available:
            Label("Available", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unavailable(.deviceNotEligible):
            Label("This Mac is not eligible", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        case .unavailable(.systemNotReady):
            Label("Temporarily unavailable — using on-device model", systemImage: "clock")
                .foregroundStyle(.secondary)
        @unknown default:
            Label("Unavailable — using on-device model", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
        }

        if let suggestion = model.quotaUsage.limitIncreaseSuggestion {
            Button("Show usage options") {
                suggestion.show()
            }
        }
    }
}
#endif
