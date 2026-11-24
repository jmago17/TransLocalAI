import SwiftUI
import ThinkingOrbs
import UniformTypeIdentifiers

struct MacMainView: View {
    @State private var language = "auto"
    @State private var engine: EnginePreference = .auto
    @State private var modelProgress = 0.0
    @State private var transcriptionTask: Task<Void, Never>?
    private var effectiveEngineName: String {
        if engine == .voz && (language == "multilingual" || VozLanguagePolicy.base(language) == "eu") { return "WhisperKit" }
        return engine.rawValue
    }
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
                .disabled(isWorking)
                Section("Transcription") {
                    Picker("Language", selection: $language) {
                        Text("Auto-detect").tag("auto")
                        Text("Multilingual · WhisperKit").tag("multilingual")
                        Text("Euskara · WhisperKit").tag("eu-ES")
                        ForEach(VozLanguagePolicy.supported.sorted(), id: \.self) { code in
                            Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
                        }
                    }
                    Picker("Engine", selection: $engine) {
                        Text("Auto").tag(EnginePreference.auto)
                        Text("Apple").tag(EnginePreference.apple)
                        Text("WhisperKit").tag(EnginePreference.whisper)
                        if VozLanguagePolicy.supports(language) || engine == .voz {
                            Text(VozLanguagePolicy.supports(language) ? "Voz" : "Voz · unavailable").tag(EnginePreference.voz)
                        }
                    }
                    if engine == .voz { VozInformationView() }
                    if language == "multilingual" || VozLanguagePolicy.base(language) == "eu" {
                        Text("Euskara and multilingual audio use WhisperKit, including a previous Voz selection.").font(.caption)
                    }
                    if isWorking { ProgressView("Preparing / transcribing · \(effectiveEngineName)", value: modelProgress) }
                }
                .disabled(isWorking)
                if transcriptionTask != nil {
                    Button("Cancel transcription") { transcriptionTask?.cancel() }
                    Text("Cancellation may wait for the current SDK operation.").font(.caption)
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
                        if isWorking { ThinkingOrb(.composing, size: .small).accessibilityLabel("Working…") } else { Label("Create Notes", systemImage: "sparkles") }
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
        modelProgress = 0
        let requestLanguage = language
        let requestEngine = engine
        let scoped = url.startAccessingSecurityScopedResource()
        transcriptionTask = Task {
            defer { if scoped { url.stopAccessingSecurityScopedResource() }; isWorking = false; transcriptionTask = nil }
            do {
                let result = try await MacTranscriber.transcribe(audioURL: url, language: requestLanguage, engine: requestEngine) { value in
                    Task { @MainActor in modelProgress = value }
                }
                try Task.checkCancellation()
                transcript = result
                if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            } catch is CancellationError {
                // Keep the previous transcript.
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
