import SwiftUI
import SwiftData
import AVFoundation

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// `true` when this is the permanent content of the Record tab rather
    /// than a sheet (`ContentView`'s "New Recording" flow) — finishing
    /// resets back to `setupView` instead of dismissing a sheet that isn't
    /// there.
    var embedded: Bool = false

    var recorder: AudioRecorderManager { AudioRecorderManager.shared }

    @State private var recordingName = ""
    @State private var hasStarted = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasStopped = false
    @State private var stoppedFileURL: URL?
    /// Library entry created the moment recording stops, so the audio is in
    /// the library even if the user never taps Save/Transcribe or the app
    /// dies on this screen. "Transcribe Now" fills it in.
    @State private var savedTranscription: Transcription?
    @State private var isTranscribing = false
    @State private var isPreparingModel = false
    @State private var preparationProgress = 0.0
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var hasPermission: Bool?
    @State private var selectedLanguage = "multilingual"
    @State private var selectedEngine: EnginePreference = .auto
    @State private var selectedModelIdentifier = WhisperModelCatalog.defaultModelIdentifier

    private let hybridService = HybridTranscriptionService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let hasPermission, !hasPermission {
                    permissionDeniedView
                } else if isTranscribing {
                    transcribingView
                } else if hasStopped, let url = stoppedFileURL {
                    recordingCompleteView(url: url)
                } else if hasStarted {
                    activeRecordingView
                } else {
                    setupView
                }
            }
            .padding()
            .liquidCrystalScreen()
            .navigationTitle("Record Audio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Embebida en el tab, "Cancel" solo tiene sentido mientras
                // graba de verdad — antes de eso no hay nada que cancelar
                // ni una hoja que cerrar.
                if !embedded || (hasStarted && !hasStopped) {
                    ToolbarItem(placement: .cancellationAction) {
                        // After Stop the audio is already in the library, so
                        // closing keeps it — say so instead of "Cancel".
                        Button(hasStopped && !isTranscribing ? "Done" : "Cancel") {
                            if isTranscribing {
                                transcriptionTask?.cancel()
                            } else {
                                if hasStarted && !hasStopped { recorder.cancelRecording() }
                                finish()
                            }
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .task {
                if hasPermission == nil {
                    hasPermission = await recorder.requestPermission()
                }
                // Sync with a recording already started externally (e.g. via Shortcut)
                if recorder.isRecording && !hasStarted {
                    hasStarted = true
                }
            }
            .onChange(of: recorder.isRecording) { _, isRecording in
                // Recording stopped externally (Live Activity button or Shortcut intent)
                if !isRecording && hasStarted && !hasStopped {
                    finish()
                }
            }
        }
    }

    /// Vuelve al estado inicial (tab persistente) o cierra la hoja (uso
    /// modal desde `ContentView`) — ver `embedded`.
    private func finish() {
        transcriptionTask?.cancel()
        if embedded {
            hasStarted = false
            hasStopped = false
            stoppedFileURL = nil
            savedTranscription = nil
            recordingName = ""
            isTranscribing = false
        } else {
            dismiss()
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Microphone Access Required")
                .font(.title3.weight(.semibold))

            Text("Enable microphone access in Settings to record audio.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var setupView: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.red)

            TextField("Recording Name", text: $recordingName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Button(action: startRecording) {
                Label("Start Recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(hasPermission == nil)
        }
    }

    private var activeRecordingView: some View {
        VStack(spacing: 24) {
            // Recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(recorder.isPaused ? .orange : .red)
                    .frame(width: 12, height: 12)
                    .opacity(recorder.isRecording && !recorder.isPaused ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: recorder.isRecording)

                Text(recorder.isPaused ? "Paused" : "Recording")
                    .font(.headline)
                    .foregroundStyle(recorder.isPaused ? .orange : .red)
            }

            if recorder.isPaused {
                VStack(spacing: 8) {
                    Text("Another app or a call interrupted the microphone. What was recorded so far is safe.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        if !recorder.resumeRecording() {
                            errorMessage = String(localized: "The microphone is still in use by another app. Try again when it is free.")
                            showError = true
                        }
                    } label: {
                        Label("Resume Recording", systemImage: "record.circle")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }

            // Elapsed time
            Text(recorder.formattedElapsedTime)
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .contentTransition(.numericText())

            // Audio level meter
            AudioLevelView(level: recorder.audioLevel)
                .frame(height: 40)
                .padding(.horizontal)

            Text(recorder.recordingTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: stopRecording) {
                Label("Stop Recording", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
    }

    private func recordingCompleteView(url: URL) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Recording Complete")
                .font(.title3.weight(.semibold))

            Text(recorder.formattedElapsedTime)
                .font(.headline)
                .foregroundStyle(.secondary)

            // Language selector
            VStack(alignment: .leading, spacing: 6) {
                Text("Language")
                    .font(.headline)

                Picker("Language", selection: $selectedLanguage) {
                    Text("Multilingual").tag("multilingual")
                    Text("Euskara").tag("eu-ES")
                    Text("Español").tag("es-ES")
                    Text("English").tag("en-US")
                    ForEach(VozLanguagePolicy.supported.subtracting(["en", "es"]).sorted(), id: \.self) { code in
                        Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
                    }
                }
                .pickerStyle(.menu)

                Text(languageHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TranscriptionModelPicker(
                engine: $selectedEngine,
                modelIdentifier: $selectedModelIdentifier,
                language: selectedLanguage
            )

            Spacer()

            Button(action: { transcribeRecording(url: url) }) {
                Label("Transcribe Now", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: { saveAudioOnly(url: url) }) {
                Label("Save Audio Only", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var transcribingView: some View {
        VStack(spacing: 24) {
            TranscribingAnimation()

            Text(isPreparingModel ? "Preparing \(hybridService.engineKind(for: selectedLanguage, engine: selectedEngine).displayName) model..." : "Transcribing...")
                .font(.headline)

            if isPreparingModel { ProgressView(value: preparationProgress) }
            Button("Cancel transcription") { transcriptionTask?.cancel() }
            Text("This may take a few moments. Voz's initial load can take 10–30 seconds; cancellation may wait for the current SDK operation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func startRecording() {
        let title = recordingName.isEmpty
            ? "Recording \(Date().formatted(date: .abbreviated, time: .shortened))"
            : recordingName

        do {
            try recorder.startRecording(title: title)
            hasStarted = true
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            showError = true
        }
    }

    private func stopRecording() {
        guard let url = recorder.stopRecording() else { return }
        let transcription = Transcription(
            title: recorder.recordingTitle,
            transcriptionText: "",
            language: selectedLanguage,
            duration: audioDuration(url: url),
            audioFileURL: url.lastPathComponent,
            engineUsed: ""
        )
        modelContext.insert(transcription)
        do {
            try modelContext.save()
            PendingRecordings.remove(fileName: url.lastPathComponent)
        } catch {
            // The pending mark stays, so recovery retries on next launch.
        }
        savedTranscription = transcription
        stoppedFileURL = url
        hasStopped = true
    }

    private func saveAudioOnly(url: URL) {
        if let savedTranscription {
            savedTranscription.language = selectedLanguage
            try? modelContext.save()
        }
        finish()
    }

    private var languageHint: String {
        switch selectedLanguage {
        case "multilingual":
            return String(localized: "Auto-detects language (may misidentify mixed-language audio)")
        case "eu-ES":
            return String(localized: "Force Basque — best for Basque-dominant recordings")
        case "es-ES":
            return String(localized: "Force Spanish — best for Spanish-dominant recordings")
        case "en-US":
            return String(localized: "Force English — best for English-dominant recordings")
        default:
            return ""
        }
    }

    private func transcribeRecording(url: URL) {
        isTranscribing = true

        transcriptionTask = Task {
            defer { isPreparingModel = false; isTranscribing = false; transcriptionTask = nil }
            do {
                isPreparingModel = hybridService.engineKind(for: selectedLanguage, engine: selectedEngine) != .appleSpeech
                preparationProgress = 0
                try await hybridService.prepareModelIfNeeded(language: selectedLanguage, engine: selectedEngine, modelIdentifier: selectedModelIdentifier) { value in
                    Task { @MainActor in preparationProgress = value }
                }
                isPreparingModel = false
                try Task.checkCancellation()

                let result = try await hybridService.transcribe(
                    audioURL: url,
                    language: selectedLanguage,
                    engine: selectedEngine,
                    modelIdentifier: selectedModelIdentifier
                )

                try Task.checkCancellation()
                let transcription: Transcription
                if let savedTranscription {
                    transcription = savedTranscription
                } else {
                    transcription = Transcription(
                        title: recorder.recordingTitle,
                        transcriptionText: "",
                        language: result.language,
                        duration: result.duration,
                        audioFileURL: url.lastPathComponent,
                        engineUsed: ""
                    )
                    modelContext.insert(transcription)
                }
                transcription.transcriptionText = result.text
                transcription.language = result.language
                transcription.duration = result.duration
                transcription.engineUsed = result.engineUsed.persistedValue
                transcription.segmentTimings = TranscriptSegments.encode(result.segmentTimings)
                try modelContext.save()

                isTranscribing = false
                finish()
            } catch is CancellationError {
                // Keep the recording available for another attempt.
            } catch {
                isTranscribing = false
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func audioDuration(url: URL) -> TimeInterval {
        RecordingRecovery.audioDuration(url: url)
    }
}

// MARK: - Audio Level Visualization

private struct AudioLevelView: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<30, id: \.self) { index in
                    let threshold = Float(index) / 30.0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: threshold))
                        .opacity(level >= threshold ? 1 : 0.15)
                }
            }
        }
    }

    private func barColor(for threshold: Float) -> Color {
        if threshold > 0.8 { return .red }
        if threshold > 0.6 { return .orange }
        return .green
    }
}

#Preview {
    RecordingView()
        .modelContainer(for: Transcription.self, inMemory: true)
}
