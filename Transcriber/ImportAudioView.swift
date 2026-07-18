//
//  ImportAudioView.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AVFoundation
import Foundation
import Speech
import BackgroundTasks

struct ImportAudioView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showFilePicker = false
    @State private var selectedLanguage = "en-US"
    @State private var selectedEngine: EnginePreference = .auto
    @State private var useAutoDetect = true
    @State private var isDetectingLanguage = false
    @State private var isTranscribing = false
    @State private var isPreparingWhisperModel = false
    @State private var whisperDownloadProgress: Double = 0
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedFileURL: URL?
    private let hybridService = HybridTranscriptionService()
    @State private var hasPermission = false
    @State private var transcriptionTask: Task<Void, Never>?  // Track the transcription task
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    if !hasPermission {
                        permissionsView
                    } else if selectedFileURL == nil {
                        fileSelectionView
                    } else if isTranscribing {
                        transcribingView
                    } else {
                        fileSelectedView
                    }
                }
                .padding()
            }
            .liquidCrystalScreen()
            .navigationTitle("Import Audio")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isTranscribing {
                            // Cancel the transcription task
                            transcriptionTask?.cancel()
                            isTranscribing = false
                            isDetectingLanguage = false
                        }
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            await checkPermissions()
        }
    }
    
    private var permissionsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            Text("Speech Recognition Access")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            Text("This app needs speech recognition permission to transcribe audio files.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            Button("Grant Permission") {
                Task {
                    await checkPermissions()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var fileSelectionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Select an audio file to transcribe")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            Text("Supported formats: MP3, M4A, WAV, and more")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Settings section
            VStack(alignment: .leading, spacing: 12) {
                // Language selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("Language")
                        .font(.headline)

                    Toggle("Auto-detect language", isOn: $useAutoDetect)
                        .tint(.accentColor)

                    if !useAutoDetect {
                        Picker("Language", selection: $selectedLanguage) {
                            Text("English (US)").tag("en-US")
                            Text("Spanish (Spain)").tag("es-ES")
                            Text("Basque (Euskara)").tag("eu-ES")
                            Text("Multilingual").tag("multilingual")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedLanguage) {
                            if selectedLanguage == "multilingual" {
                                selectedEngine = .whisper
                            }
                        }
                    } else {
                        Text("Language will be automatically detected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Engine selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("Engine")
                        .font(.headline)

                    Picker("Engine", selection: $selectedEngine) {
                        ForEach(EnginePreference.allCases) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(selectedLanguage == "multilingual")

                    Text(engineDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            
            Button(action: { showFilePicker = true }) {
                Label("Choose Audio File", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    private var fileSelectedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            if let url = selectedFileURL {
                VStack(spacing: 8) {
                    Text("File Selected")
                        .font(.headline)
                    Text(url.lastPathComponent)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            
            Spacer()
            
            Button(action: transcribeAudio) {
                Label("Start Transcription", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Button(action: {
                selectedFileURL = nil
            }) {
                Label("Choose Different File", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
    
    private var transcribingView: some View {
        VStack(spacing: 30) {
            TranscribingAnimation()
            
            if isDetectingLanguage {
                Text("Detecting language...")
                    .font(.headline)
                
                Text("Analyzing audio to determine the best language")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if isPreparingWhisperModel {
                Text("Downloading Whisper model...")
                    .font(.headline)

                ProgressView(value: whisperDownloadProgress)
                    .frame(maxWidth: 220)

                Text("This is a one-time download and will be reused offline")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Transcribing audio...")
                    .font(.headline)
                
                Text("This may take a few moments")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var engineDescription: String {
        if selectedLanguage == "multilingual" {
            return "Multilingual mode requires WhisperKit for per-segment language detection."
        }
        switch selectedEngine {
        case .auto:
            return "Apple Speech for most languages; WhisperKit for Euskara."
        case .apple:
            return "Apple SpeechAnalyzer: fast, on-device transcription."
        case .whisper:
            return "WhisperKit: open-source model, runs on-device."
        }
    }

    private func checkPermissions() async {
        hasPermission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        if !hasPermission {
            errorMessage = "Speech recognition permission is required to transcribe audio."
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Copy the selected file into this device's app storage.
            do {
                // Preserve original filename with timestamp to avoid conflicts
                let originalName = url.deletingPathExtension().lastPathComponent
                let fileExtension = url.pathExtension
                let timestamp = Date().timeIntervalSince1970
                let sanitizedName = originalName.replacingOccurrences(of: " ", with: "-")
                let filename = "\(sanitizedName)-\(Int(timestamp)).\(fileExtension)"
                let destinationURL = AudioFileManager.shared.audioDirectory.appendingPathComponent(filename)
                
                // Start accessing security-scoped resource
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                try FileManager.default.copyItem(at: url, to: destinationURL)
                selectedFileURL = destinationURL
            } catch {
                errorMessage = "Failed to import file: \(error.localizedDescription)"
                showError = true
            }
            
        case .failure(let error):
            errorMessage = "File selection failed: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func transcribeAudio() {
        guard let audioURL = selectedFileURL else { return }

        // A continued-processing task is what keeps CPU/Core ML work alive after
        // the app moves to the background. Its system UI also acts as a Live Activity.
        let bgTaskRequest = BGContinuedProcessingTaskRequest(
            identifier: TranscriberApp.bgTaskIdentifier,
            title: "Transcribing audio",
            subtitle: audioURL.lastPathComponent
        )
        bgTaskRequest.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(bgTaskRequest)
        } catch {
            // Background protection is best-effort: without it the transcription
            // still runs, it just pauses if the app is backgrounded. Refusing to
            // start here made imports fail whenever the system throttled BG tasks.
            print("Continued-processing task unavailable, transcribing in foreground: \(error)")
        }

        isTranscribing = true

        // Additional safety net: UIKit background task gives ~30s immediately when app backgrounds
        var uiBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        uiBackgroundTaskID = UIApplication.shared.beginBackgroundTask {
            // BGContinuedProcessingTask now owns the long-running work. Expiring
            // this short transition allowance must not cancel the transcription.
            if uiBackgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(uiBackgroundTaskID)
                uiBackgroundTaskID = .invalid
            }
        }

        // Wire BG task expiration to cancel the transcription
        TranscriberApp.onBGTaskExpiration = {
            self.transcriptionTask?.cancel()
        }

        transcriptionTask = Task {
            do {
                var languageToUse = selectedLanguage
                let isMultilingual = selectedLanguage == "multilingual"

                if useAutoDetect && !isMultilingual {
                    try Task.checkCancellation()
                    isDetectingLanguage = true
                    updateLiveActivity(phase: "Detecting language...", progress: 0)
                    do {
                        languageToUse = try await hybridService.detectLanguage(audioURL: audioURL)
                    } catch {
                        languageToUse = selectedLanguage
                    }
                    print("Detected language: \(languageToUse)")
                    isDetectingLanguage = false
                    // Use multilingual mode only for Basque, which commonly mixes with Spanish
                    if languageToUse == "eu-ES" {
                        languageToUse = "multilingual"
                        print("Basque detected: switching to multilingual mode for per-segment detection")
                    }
                }

                try Task.checkCancellation()

                if hybridService.engineKind(for: languageToUse, engine: selectedEngine) == .whisper {
                    isPreparingWhisperModel = true
                    whisperDownloadProgress = 0
                    updateLiveActivity(phase: "Downloading model...", progress: 0)
                    defer { isPreparingWhisperModel = false }
                    try await hybridService.prepareModelIfNeeded(language: languageToUse, engine: selectedEngine) { progress in
                        Task { @MainActor in
                            self.whisperDownloadProgress = progress
                            self.updateLiveActivity(phase: "Downloading model... \(Int(progress * 100))%", progress: progress * 0.3)
                        }
                    }
                }

                updateLiveActivity(phase: "Transcribing...", progress: 0.3)

                let result = try await hybridService.transcribe(audioURL: audioURL, language: languageToUse, engine: selectedEngine)
                let transcriptionText = result.text
                let duration = result.duration

                updateLiveActivity(phase: "Saving...", progress: 0.95)

                // Save to SwiftData
                // Extract clean title from filename (remove timestamp and file extension)
                let filename = audioURL.deletingPathExtension().lastPathComponent
                let cleanTitle: String

                // Remove timestamp pattern (e.g., "-1702677600") from the end
                if let lastDashIndex = filename.lastIndex(of: "-"),
                   let timestampPart = filename[filename.index(after: lastDashIndex)...].first,
                   timestampPart.isNumber {
                    cleanTitle = String(filename[..<lastDashIndex]).replacingOccurrences(of: "-", with: " ")
                } else {
                    cleanTitle = filename.replacingOccurrences(of: "-", with: " ")
                }

                let transcription = Transcription(
                    title: cleanTitle.capitalized,
                    transcriptionText: transcriptionText,
                    language: languageToUse,
                    duration: duration,
                    audioFileURL: audioURL.lastPathComponent,
                    engineUsed: (result.engineUsed == .appleSpeech ? "apple" : "whisper")
                )

                modelContext.insert(transcription)
                try modelContext.save()

                updateLiveActivity(phase: "Complete", progress: 1.0)

                // Signal BG tasks completed successfully
                TranscriberApp.currentBGTask?.setTaskCompleted(success: true)
                TranscriberApp.currentBGTask = nil
                TranscriberApp.onBGTaskExpiration = nil
                if uiBackgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(uiBackgroundTaskID)
                    uiBackgroundTaskID = .invalid
                }

                isTranscribing = false
                dismiss()
            } catch is CancellationError {
                // Task was cancelled - just clean up and dismiss
                isTranscribing = false
                isDetectingLanguage = false
                TranscriberApp.currentBGTask?.setTaskCompleted(success: false)
                TranscriberApp.currentBGTask = nil
                TranscriberApp.onBGTaskExpiration = nil
                if uiBackgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(uiBackgroundTaskID)
                    uiBackgroundTaskID = .invalid
                }
                print("Transcription cancelled by user")
                dismiss()
            } catch {
                isTranscribing = false
                isDetectingLanguage = false
                TranscriberApp.currentBGTask?.setTaskCompleted(success: false)
                TranscriberApp.currentBGTask = nil
                TranscriberApp.onBGTaskExpiration = nil
                if uiBackgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(uiBackgroundTaskID)
                    uiBackgroundTaskID = .invalid
                }
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    // MARK: - Continued-processing system activity

    private func updateLiveActivity(phase: String, progress: Double) {
        let boundedProgress = min(max(progress, 0), 1)
        TranscriberApp.currentBGTask?.progress.completedUnitCount = Int64(boundedProgress * 100)
        TranscriberApp.currentBGTask?.updateTitle(
            "Transcribing audio",
            subtitle: "\(phase) \(Int(boundedProgress * 100))%"
        )

    }
}

#Preview {
    ImportAudioView()
        .modelContainer(for: Transcription.self, inMemory: true)
}
