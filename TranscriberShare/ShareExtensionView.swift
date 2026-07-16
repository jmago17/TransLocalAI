import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ShareExtensionView: View {
    let extensionContext: NSExtensionContext?
    let dismiss: () -> Void

    private enum Phase: Equatable { case loading, ready, transcribing, done(String), failed(String) }

    @State private var phase: Phase = .loading
    @State private var audioURL: URL?
    @State private var name = ""
    @State private var transcribedText = ""

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading: ProgressView("Loading audio…")
                case .ready: readyView
                case .transcribing: ProgressView("Transcribing on this device…")
                case .done(let message): resultView(message, icon: "checkmark.circle.fill", color: .green)
                case .failed(let message): resultView(message, icon: "exclamationmark.triangle.fill", color: .orange)
                }
            }
            .padding()
            .navigationTitle("Transcribe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(phase == .transcribing)
                }
            }
        }
        .task { await load() }
    }

    private var readyView: some View {
        VStack {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue.gradient)
            TextField("Title", text: $name).textFieldStyle(.roundedBorder)
            Button {
                Task { await transcribeOnDevice() }
            } label: {
                Label("Transcribe on This Device", systemImage: "lock.shield")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("The audio is not sent to another computer or service.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func resultView(_ message: String, icon: String, color: Color) -> some View {
        VStack {
            Image(systemName: icon).font(.system(size: 56)).foregroundStyle(color)
            Text(message).multilineTextAlignment(.center)
            if !transcribedText.isEmpty {
                ScrollView { Text(transcribedText).textSelection(.enabled) }.frame(maxHeight: 220)
            }
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func load() async {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else { phase = .failed("No audio was found."); return }
        let types = [UTType.audio, .mpeg4Audio, .mp3, .wav, .aiff, .movie]
        for provider in attachments {
            for type in types where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                do {
                    let url = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                            if let error { continuation.resume(throwing: error); return }
                            guard let url else { continuation.resume(throwing: ShareError.fileNotFound); return }
                            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)-\(url.lastPathComponent)")
                            do { try FileManager.default.copyItem(at: url, to: copy); continuation.resume(returning: copy) }
                            catch { continuation.resume(throwing: error) }
                        }
                    }
                    audioURL = url
                    name = url.deletingPathExtension().lastPathComponent
                    phase = .ready
                    return
                } catch { phase = .failed(error.localizedDescription); return }
            }
        }
        phase = .failed("The shared file is not a supported audio file.")
    }

    private func transcribeOnDevice() async {
        guard let audioURL else { return }
        phase = .transcribing
        let manager = ShareTranscriptionManager()
        do {
            guard await manager.requestPermission() else { throw ShareError.permissionDenied }
            let language = try await manager.detectLanguage(audioURL: audioURL)
            let text = try await manager.transcribe(audioURL: audioURL, language: language)
            transcribedText = text
            try await saveTranscription(text: text, audioURL: audioURL, fileName: name, language: language)
            phase = .done("Saved to your local transcription library.")
        } catch { phase = .failed(error.localizedDescription) }
    }

    private func saveTranscription(text: String, audioURL: URL, fileName: String, language: String) async throws {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.josumartinez.transcriber") else { return }
        let audioDirectory = container.appendingPathComponent("SharedAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let savedAudio = audioDirectory.appendingPathComponent("\(UUID().uuidString).\(audioURL.pathExtension)")
        try FileManager.default.copyItem(at: audioURL, to: savedAudio)
        let pendingDirectory = container.appendingPathComponent("PendingTranscriptions", isDirectory: true)
        try FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
        let duration = (try? AVAudioFile(forReading: audioURL)).map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        let json: [String: Any] = ["title": fileName, "text": text, "language": language, "duration": duration, "audioFile": savedAudio.lastPathComponent, "timestamp": Date().timeIntervalSince1970]
        try JSONSerialization.data(withJSONObject: json).write(to: pendingDirectory.appendingPathComponent("\(UUID().uuidString).json"))
    }
}

enum ShareError: LocalizedError {
    case fileNotFound, permissionDenied
    var errorDescription: String? {
        switch self {
        case .fileNotFound: "The shared file could not be read."
        case .permissionDenied: "Speech recognition permission is required."
        }
    }
}
