import SwiftUI
import UniformTypeIdentifiers

struct MacMainView: View {
    @State private var title = ""
    @State private var transcript = ""
    @State private var notes = ""
    @State private var isWorking = false
    @State private var showingAudioImporter = false
    @State private var showingTranscriptImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            List {
                Section("Import") {
                    Button("Audio File", systemImage: "waveform") { showingAudioImporter = true }
                    Button("Transcript File", systemImage: "doc.text") { showingTranscriptImporter = true }
                }
                Section("Privacy") {
                    Label("Stored on this Mac", systemImage: "lock.shield.fill")
                    Text("Transcription stays local. Enhanced notes can process transcript text with Apple's Private Cloud Compute.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("TransLocalAI")
        } detail: {
            VStack(alignment: .leading) {
                TextField("Meeting title", text: $title)
                    .font(.title2.bold())
                HSplitView {
                    editor(title: "Transcript", text: $transcript)
                    editor(title: "Meeting Notes", text: $notes)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.caption) }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await generateNotes() }
                    } label: {
                        if isWorking { ProgressView() } else { Label("Create Notes", systemImage: "sparkles") }
                    }
                    .disabled(isWorking || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .fileImporter(isPresented: $showingAudioImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false, onCompletion: importAudio)
        .fileImporter(isPresented: $showingTranscriptImporter, allowedContentTypes: [.plainText, .text, .json, .sourceCode], allowsMultipleSelection: false, onCompletion: importTranscript)
    }

    private func editor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            TextEditor(text: text).font(.body.monospaced()).padding(6)
        }
        .frame(minWidth: 280)
    }

    private func importTranscript(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            transcript = try TranscriptFileParser.text(from: Data(contentsOf: url), extension: url.pathExtension)
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
        } catch { errorMessage = error.localizedDescription }
    }

    private func importAudio(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isWorking = true
        let scoped = url.startAccessingSecurityScopedResource()
        Task {
            defer { if scoped { url.stopAccessingSecurityScopedResource() }; isWorking = false }
            do {
                transcript = try await MacTranscriber.transcribe(audioURL: url)
                if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func generateNotes() async {
        isWorking = true
        defer { isWorking = false }
        do {
            notes = try await MeetingNotesService.generate(from: transcript, title: title)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
