import SwiftUI
import SwiftData

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var recorder: AudioRecorderManager { AudioRecorderManager.shared }

    @State private var recordingName = ""
    @State private var hasStarted = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasStopped = false
    @State private var stoppedFileURL: URL?
    @State private var isTranscribing = false
    @State private var hasPermission: Bool?

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
            .navigationTitle("Record Audio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasStarted && !hasStopped {
                            recorder.cancelRecording()
                        }
                        dismiss()
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
            }
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
                    .fill(.red)
                    .frame(width: 12, height: 12)
                    .opacity(recorder.isRecording ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: recorder.isRecording)

                Text("Recording")
                    .font(.headline)
                    .foregroundStyle(.red)
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
            ProgressView()
                .scaleEffect(1.5)

            Text("Transcribing...")
                .font(.headline)

            Text("This may take a few moments")
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
        if let url = recorder.stopRecording() {
            stoppedFileURL = url
            hasStopped = true
        }
    }

    private func saveAudioOnly(url: URL) {
        let duration = audioDuration(url: url)
        let title = recorder.recordingTitle

        let transcription = Transcription(
            title: title,
            transcriptionText: "",
            language: "en-US",
            duration: duration,
            audioFileURL: url.lastPathComponent,
            engineUsed: ""
        )

        modelContext.insert(transcription)
        try? modelContext.save()
        dismiss()
    }

    private func transcribeRecording(url: URL) {
        isTranscribing = true

        Task {
            do {
                try await hybridService.prepareModelIfNeeded(language: "multilingual") { _ in }

                let result = try await hybridService.transcribe(
                    audioURL: url,
                    language: "multilingual"
                )

                let transcription = Transcription(
                    title: recorder.recordingTitle,
                    transcriptionText: result.text,
                    language: result.language,
                    duration: result.duration,
                    audioFileURL: url.lastPathComponent,
                    engineUsed: result.engineUsed == .appleSpeech ? "apple" : "whisper"
                )

                modelContext.insert(transcription)
                try modelContext.save()

                isTranscribing = false
                dismiss()
            } catch {
                isTranscribing = false
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func audioDuration(url: URL) -> TimeInterval {
        let asset = AVURLAsset(url: url)
        return asset.duration.seconds.isNaN ? 0 : asset.duration.seconds
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

import AVFoundation

#Preview {
    RecordingView()
        .modelContainer(for: Transcription.self, inMemory: true)
}
