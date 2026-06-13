//
//  ShareExtensionView.swift
//  TranscriberShare
//
//  Receives a shared audio file and, by default, sends it to the Mac pipeline
//  (HTTP to actas-server, iCloud Inbox fallback) so it becomes an acta. The
//  user confirms the name (== Apple Notes title) first. On-device transcription
//  is kept as an explicit secondary option.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct ShareExtensionView: View {
    let extensionContext: NSExtensionContext?
    let dismiss: () -> Void

    private enum Phase: Equatable {
        case loading
        case ready
        case sending
        case transcribing
        case done(String)
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var audioURL: URL?
    @State private var name = ""
    @State private var progress: Double = 0
    @State private var transcribedText = ""

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:    loadingView
                case .ready:      readyView
                case .sending:    sendingView
                case .transcribing: transcribingView
                case .done(let msg):   doneView(msg)
                case .failed(let msg): failedView(msg)
                }
            }
            .padding()
            .navigationTitle("Enviar acta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(phase == .sending || phase == .transcribing)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Phases

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4)
            Text("Cargando audio…").foregroundStyle(.secondary)
        }
    }

    private var readyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue.gradient)

            VStack(alignment: .leading, spacing: 6) {
                Text("Título del acta").font(.caption).foregroundStyle(.secondary)
                TextField("Nombre", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Text("Debe coincidir con la nota en Apple Notes (carpeta «Actas»).")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            Button {
                Task { await sendToMac() }
            } label: {
                Label("Enviar al Mac", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                Task { await transcribeOnDevice() }
            } label: {
                Label("Transcribir en el dispositivo", systemImage: "iphone")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    private var sendingView: some View {
        VStack(spacing: 18) {
            ProgressView(value: progress) {
                Text("Enviando al Mac…").font(.headline)
            }
            Text(name).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var transcribingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.4)
            Text("Transcribiendo en el dispositivo…").font(.headline)
            Text("Esto puede tardar un poco.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func doneView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60)).foregroundStyle(.green)
            Text("Listo").font(.title2.bold())
            Text(message).font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !transcribedText.isEmpty {
                ScrollView {
                    Text(transcribedText).font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 200)
            }
            Button("Hecho") { dismiss() }.buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56)).foregroundStyle(.orange)
            Text("No se pudo enviar").font(.title2.bold())
            Text(message).font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Reintentar") { phase = .ready }.buttonStyle(.borderedProminent)
            Button("Cerrar") { dismiss() }.buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Load shared file

    private func load() async {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            phase = .failed("No se encontró ningún audio."); return
        }
        let types = [UTType.audio, .mpeg4Audio, .mp3, .wav, .aiff, .movie]
        for provider in attachments {
            for type in types where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                do {
                    let url = try await loadFile(from: provider, typeIdentifier: type.identifier)
                    audioURL = url
                    name = url.deletingPathExtension().lastPathComponent
                    phase = .ready
                    return
                } catch {
                    phase = .failed(error.localizedDescription); return
                }
            }
        }
        phase = .failed("El archivo compartido no es un audio compatible.")
    }

    private func loadFile(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error { continuation.resume(throwing: error); return }
                guard let url else { continuation.resume(throwing: ShareError.fileNotFound); return }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("share-\(UUID().uuidString)-\(url.lastPathComponent)")
                do {
                    try? FileManager.default.removeItem(at: tempURL)
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    continuation.resume(returning: tempURL)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    // MARK: - Send to Mac (HTTP primary, iCloud fallback)

    private func sendToMac() async {
        guard let audioURL else { return }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .sending
        progress = 0

        // 1) HTTP
        do {
            _ = try await ActasServerClient.shared.upload(
                fileURL: audioURL, displayName: title,
                progress: { p in Task { @MainActor in progress = max(progress, p) } })
            phase = .done("«\(title)» está en la cola del Mac. La transcripción arrancará en breve.")
            return
        } catch {
            // fall through to iCloud
        }

        // 2) iCloud fallback
        if ICloudInboxBridge.isConfigured {
            do {
                _ = try ICloudInboxBridge.writeAudioToInbox(from: audioURL, displayName: title)
                phase = .done("El Mac no respondía; «\(title)» se guardó en iCloud y se procesará al sincronizar.")
                return
            } catch {
                phase = .failed("HTTP e iCloud fallaron: \(error.localizedDescription)")
                return
            }
        }

        phase = .failed("El Mac no responde y no hay carpeta iCloud configurada. Abre la app → Ajustes para emparejar o elegir la carpeta Reuniones.")
    }

    // MARK: - On-device transcription (explicit secondary path)

    private func transcribeOnDevice() async {
        guard let audioURL else { return }
        phase = .transcribing
        let manager = ShareTranscriptionManager()
        do {
            guard await manager.requestPermission() else { throw ShareError.permissionDenied }
            let language = try await manager.detectLanguage(audioURL: audioURL)
            let text = try await manager.transcribe(audioURL: audioURL, language: language)
            transcribedText = text
            try? await saveTranscription(text: text, audioURL: audioURL,
                                         fileName: name.trimmingCharacters(in: .whitespaces))
            phase = .done("Transcrito en el dispositivo. Aparecerá en la Biblioteca de la app.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func saveTranscription(text: String, audioURL: URL, fileName: String) async throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.josumartinez.transcriber") else { return }

        let audioDir = containerURL.appendingPathComponent("SharedAudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let savedAudio = audioDir.appendingPathComponent("\(UUID().uuidString).\(audioURL.pathExtension)")
        try? FileManager.default.copyItem(at: audioURL, to: savedAudio)

        let pendingDir = containerURL.appendingPathComponent("PendingTranscriptions", isDirectory: true)
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)

        let duration: TimeInterval
        if let f = try? AVAudioFile(forReading: audioURL) {
            duration = Double(f.length) / f.fileFormat.sampleRate
        } else { duration = 0 }

        let payload: [String: Any] = [
            "title": fileName.isEmpty ? "Acta compartida" : fileName,
            "text": text, "language": "auto", "duration": duration,
            "audioFile": savedAudio.lastPathComponent,
            "timestamp": Date().timeIntervalSince1970,
        ]
        try JSONSerialization.data(withJSONObject: payload)
            .write(to: pendingDir.appendingPathComponent("\(UUID().uuidString).json"))
    }
}

enum ShareError: LocalizedError {
    case fileNotFound
    case permissionDenied
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "No se pudo cargar el audio."
        case .permissionDenied: return "Hace falta permiso de reconocimiento de voz."
        case .transcriptionFailed: return "No se pudo transcribir el audio."
        }
    }
}
