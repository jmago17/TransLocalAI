import SwiftUI

struct LocalSettingsView: View {
    @AppStorage("liquidGlassTheme") private var liquidGlassTheme = false
    @State private var vocabularyText = TranscriptionVocabulary.terms.joined(separator: "\n")

    var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    Label("Audio, transcripts, and notes stay on this device", systemImage: "lock.shield.fill")
                    Text("No companion computer, server, account, or network connection is used for processing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Transcription") {
                    LabeledContent("Automatic engine", value: "Apple Speech")
                    LabeledContent("Euskara / multilingual", value: "Whisper Large v3")
                    LabeledContent("Whisper download", value: "About 626 MB")
                }

                Section {
                    TextEditor(text: $vocabularyText)
                        .frame(minHeight: 140)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: vocabularyText) { _, value in
                            TranscriptionVocabulary.terms = value.components(separatedBy: .newlines)
                        }
                } header: {
                    Text("Names and companies")
                } footer: {
                    Text("One short name or phrase per line, up to 100. Apple Speech uses these words as recognition context.")
                }

                Section("Appearance") {
                    Toggle("Liquid Glass", isOn: $liquidGlassTheme)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
