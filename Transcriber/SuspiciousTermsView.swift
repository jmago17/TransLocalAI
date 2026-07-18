import SwiftUI
import SwiftData

/// Lists words in a transcript that look misheard (capitalized mid-sentence,
/// unknown to the vocabulary) and offers one-tap replacement. Every fix is
/// saved as a vocabulary alias so future transcriptions get it right.
struct SuspiciousTermsView: View {
    @Bindable var transcription: Transcription
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var suspects: [TranscriptionVocabulary.SuspiciousTerm] = []
    @State private var editingTerm: TranscriptionVocabulary.SuspiciousTerm?
    @State private var replacementText = ""

    var body: some View {
        NavigationStack {
            Group {
                if suspects.isEmpty {
                    ContentUnavailableView(
                        "Nothing suspicious",
                        systemImage: "checkmark.seal.fill",
                        description: Text("Every name in this transcript matches your vocabulary or looks ordinary.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(suspects) { suspect in
                                Button {
                                    editingTerm = suspect
                                    replacementText = suspect.suggestion ?? ""
                                } label: {
                                    row(for: suspect)
                                }
                                .buttonStyle(.plain)
                            }
                        } footer: {
                            Text("Tap a word to replace it everywhere. Fixes are added to your names list, so the next transcription gets them right automatically.")
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .liquidCrystalScreen()
            .navigationTitle("Suspicious Words")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert(
                "Replace “\(editingTerm?.word ?? "")”",
                isPresented: Binding(
                    get: { editingTerm != nil },
                    set: { if !$0 { editingTerm = nil } }
                )
            ) {
                TextField("Correct spelling", text: $replacementText)
                    .autocorrectionDisabled()
                Button("Replace & Save") { applyReplacement() }
                Button("Cancel", role: .cancel) { editingTerm = nil }
            } message: {
                Text("Replaces every occurrence and adds it to your names list.")
            }
            .onAppear(perform: refresh)
        }
    }

    private func row(for suspect: TranscriptionVocabulary.SuspiciousTerm) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(suspect.word)
                    .font(.body.weight(.medium))
                if let suggestion = suspect.suggestion {
                    Label("Did you mean \(suggestion)?", systemImage: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if suspect.count > 1 {
                Text("×\(suspect.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func refresh() {
        suspects = TranscriptionVocabulary.suspiciousTerms(
            in: transcription.transcriptionText,
            terms: TranscriptionVocabulary.terms
        )
    }

    private func applyReplacement() {
        guard let term = editingTerm else { return }
        let canonical = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        editingTerm = nil
        guard !canonical.isEmpty else { return }

        TranscriptionVocabulary.addAlias(canonical: canonical, variant: term.word)
        transcription.transcriptionText = TranscriptionVocabulary.correcting(
            transcription.transcriptionText,
            terms: ["\(canonical) = \(term.word)"]
        )
        try? modelContext.save()
        refresh()
    }
}
