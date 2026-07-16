import SwiftUI

struct MacSettingsView: View {
    @State private var vocabulary = TranscriptionVocabulary.terms.joined(separator: "\n")

    var body: some View {
        Form {
            Section("Names and companies") {
                TextEditor(text: $vocabulary)
                    .frame(minHeight: 160)
                    .onChange(of: vocabulary) { _, value in
                        TranscriptionVocabulary.terms = value.components(separatedBy: .newlines)
                    }
                Text("One name or company per line. These terms improve local Apple Speech recognition.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Models") {
                LabeledContent("Automatic", value: "Apple Speech")
                LabeledContent("Euskara / multilingual", value: "Whisper Large v3 (626 MB)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 360)
    }
}
