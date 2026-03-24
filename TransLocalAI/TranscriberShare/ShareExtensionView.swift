//
//  ShareExtensionView.swift
//  TranscriberShare
//
//  Created by Josu Martinez Gonzalez on 19/12/25.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ShareExtensionView: View {
    let extensionContext: NSExtensionContext?
    let dismiss: () -> Void

    @State private var isProcessing = false
    @State private var isTranscribing = false
    @State private var progress: String = "Preparing..."
    @State private var errorMessage: String?
    @State private var transcriptionComplete = false
    @State private var transcribedText = ""
    @State private var fileName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let error = errorMessage {
                    errorView(message: error)
                } else if transcriptionComplete {
                    successView
                } else {
                    processingView
                }
            }
            .padding()
            .navigationTitle("Transcriber")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isTranscribing)
                }

                if transcriptionComplete {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .task {
            await handleSharedContent()
        }
    }

    private var processingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(progress)
                .font(.headline)

            if !fileName.isEmpty {
                Text(fileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            Text("This may take a moment")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Transcription Complete!")
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView {
                Text(transcribedText)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }
            .frame(maxHeight: 300)

            HStack(spacing: 16) {
                Button {
                    shareText(transcribedText)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    UIPasteboard.general.string = transcribedText
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Transcription Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func shareText(_ text: String) {
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        // In an app extension, walk the view hierarchy to find the presenting view controller
        guard let scene = UIApplication.value(forKeyPath: "sharedApplication.connectedScenes") as? Set<UIScene>,
              let windowScene = scene.first as? UIWindowScene,
              let rootVC = windowScene.keyWindow?.rootViewController else { return }
        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        activityVC.popoverPresentationController?.sourceView = presenter.view
        presenter.present(activityVC, animated: true)
    }

    private func handleSharedContent() async {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            errorMessage = "No audio file found"
            return
        }

        // Find audio attachment
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
                await processAudioProvider(provider, typeIdentifier: UTType.audio.identifier)
                return
            }
            // Also check for specific audio types
            for audioType in [UTType.mpeg4Audio, UTType.mp3, UTType.wav, UTType.aiff] {
                if provider.hasItemConformingToTypeIdentifier(audioType.identifier) {
                    await processAudioProvider(provider, typeIdentifier: audioType.identifier)
                    return
                }
            }
            // Check for movie (video files often contain audio)
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                await processAudioProvider(provider, typeIdentifier: UTType.movie.identifier)
                return
            }
        }

        errorMessage = "No supported audio file found"
    }

    private func processAudioProvider(_ provider: NSItemProvider, typeIdentifier: String) async {
        isProcessing = true
        progress = "Loading audio file..."

        do {
            let url = try await loadFile(from: provider, typeIdentifier: typeIdentifier)
            fileName = url.lastPathComponent

            // Copy to temporary location for processing
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("share-\(UUID().uuidString).\(url.pathExtension)")

            try FileManager.default.copyItem(at: url, to: tempURL)

            // Transcribe the audio
            progress = "Transcribing..."
            isTranscribing = true

            let transcription = try await transcribeAudio(url: tempURL)

            // Save to app's shared container
            try await saveTranscription(
                text: transcription,
                audioURL: tempURL,
                fileName: url.deletingPathExtension().lastPathComponent
            )

            transcribedText = transcription
            transcriptionComplete = true
            isTranscribing = false

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

        } catch {
            errorMessage = error.localizedDescription
            isTranscribing = false
        }

        isProcessing = false
    }

    private func loadFile(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    // Copy to temp location since the provided URL is temporary
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(url.lastPathComponent)
                    do {
                        try? FileManager.default.removeItem(at: tempURL)
                        try FileManager.default.copyItem(at: url, to: tempURL)
                        continuation.resume(returning: tempURL)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(throwing: ShareError.fileNotFound)
                }
            }
        }
    }

    private func transcribeAudio(url: URL) async throws -> String {
        // Use the shared transcription manager
        let manager = ShareTranscriptionManager()

        // Request permission first
        let hasPermission = await manager.requestPermission()
        guard hasPermission else {
            throw ShareError.permissionDenied
        }

        progress = "Detecting language..."
        let language = try await manager.detectLanguage(audioURL: url)

        progress = "Transcribing audio..."
        return try await manager.transcribe(audioURL: url, language: language)
    }

    private func saveTranscription(text: String, audioURL: URL, fileName: String) async throws {
        // Get shared app group container
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.josumartinez.transcriber"
        ) else {
            // Fallback: just complete without saving to main app
            return
        }

        // Copy audio to shared container
        let audioDirectory = containerURL.appendingPathComponent("SharedAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        let savedAudioURL = audioDirectory.appendingPathComponent("\(fileName)-\(Int(Date().timeIntervalSince1970)).\(audioURL.pathExtension)")
        try? FileManager.default.copyItem(at: audioURL, to: savedAudioURL)

        // Create a pending transcription file that main app can pick up
        let pendingDirectory = containerURL.appendingPathComponent("PendingTranscriptions", isDirectory: true)
        try? FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)

        let pendingFile = pendingDirectory.appendingPathComponent("\(UUID().uuidString).json")

        // Get duration
        let duration: TimeInterval
        if let audioFile = try? AVAudioFile(forReading: audioURL) {
            duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        } else {
            duration = 0
        }

        let pendingData: [String: Any] = [
            "title": fileName.replacingOccurrences(of: "-", with: " ").capitalized,
            "text": text,
            "language": "auto",
            "duration": duration,
            "audioFile": savedAudioURL.lastPathComponent,
            "timestamp": Date().timeIntervalSince1970
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: pendingData)
        try jsonData.write(to: pendingFile)
    }
}

enum ShareError: LocalizedError {
    case fileNotFound
    case permissionDenied
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Could not load the audio file"
        case .permissionDenied:
            return "Speech recognition permission is required"
        case .transcriptionFailed:
            return "Failed to transcribe the audio"
        }
    }
}
