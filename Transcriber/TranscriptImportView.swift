import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TranscriptImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var transcript = ""
    @State private var showingFileImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Choose Transcript File", systemImage: "doc.badge.plus")
                    }
                    Text("TXT, Markdown, SRT, VTT, and JSON files are supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Meeting") {
                    TextField("Title", text: $title)
                    TextEditor(text: $transcript)
                        .frame(minHeight: 260)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Transcript")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: save)
                        .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.plainText, .text, .json, .sourceCode],
                allowsMultipleSelection: false,
                onCompletion: load
            )
        }
    }

    private func load(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            transcript = try TranscriptFileParser.text(from: data, extension: url.pathExtension)
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        modelContext.insert(Transcription(
            title: cleanTitle,
            transcriptionText: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            language: "unknown",
            engineUsed: "imported"
        ))
        try? modelContext.save()
        dismiss()
    }
}
