//
//  MacTranscriber.swift
//  TranscriberMac
//
//  Dispatches transcription to the engine the user picked: Apple Speech or
//  WhisperKit (reusing the shared Core engines) or whisper.cpp via the external
//  CLI (Mac-only, mirrors transcribir-reunion.sh).
//

import Foundation
import AVFoundation

enum MacTranscriberError: LocalizedError {
    case toolMissing(String)
    case toolFailed(String)
    var errorDescription: String? {
        switch self {
        case .toolMissing(let p): return "No se encontró \(p)."
        case .toolFailed(let m): return m
        }
    }
}

@MainActor
enum MacTranscriber {
    /// Transcribe an audio file with the configured backend. Returns the text.
    static func transcribe(audioURL: URL) async throws -> String {
        switch MacSettings.shared.transcribe {
        case .appleSpeech:
            let engine = AppleSpeechEngine()
            let lang = (try? await engine.detectLanguage(audioURL: audioURL)) ?? "es-ES"
            return try await engine.transcribe(audioURL: audioURL, language: lang).text
        case .whisperKit:
            let service = HybridTranscriptionService()
            let lang = try await service.detectLanguage(audioURL: audioURL)
            try await service.prepareModelIfNeeded(language: lang, progress: nil)
            return try await service.transcribe(audioURL: audioURL, language: lang).text
        case .whisperCpp:
            return try await whisperCpp(audioURL: audioURL)
        }
    }

    // MARK: - whisper.cpp CLI

    private static func whisperCpp(audioURL: URL) async throws -> String {
        let s = MacSettings.shared
        let bin = s.whisperCppBin, model = s.whisperCppModel
        guard FileManager.default.isExecutableFile(atPath: bin) else { throw MacTranscriberError.toolMissing(bin) }
        guard FileManager.default.fileExists(atPath: model) else { throw MacTranscriberError.toolMissing(model) }

        let tmp = FileManager.default.temporaryDirectory
        let wav = tmp.appendingPathComponent("tla-\(UUID().uuidString).wav")
        let outBase = tmp.appendingPathComponent("tla-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: wav)
            try? FileManager.default.removeItem(at: outBase.appendingPathExtension("txt"))
        }

        // 1) ffmpeg → 16 kHz mono WAV
        try await runProcess("/opt/homebrew/bin/ffmpeg",
            ["-y", "-i", audioURL.path, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav.path],
            fallback: "/usr/local/bin/ffmpeg")

        // 2) whisper-cli → <outBase>.txt
        try await runProcess(bin,
            ["-m", model, "-f", wav.path, "--output-txt", "-of", outBase.path], fallback: nil)

        let txt = outBase.appendingPathExtension("txt")
        guard let text = try? String(contentsOf: txt, encoding: .utf8) else {
            throw MacTranscriberError.toolFailed("whisper-cli no produjo salida")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runProcess(_ path: String, _ args: [String], fallback: String?) async throws {
        let exe = FileManager.default.isExecutableFile(atPath: path) ? path
            : (fallback.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil })
        guard let exe else { throw MacTranscriberError.toolMissing(path) }
        try await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = args
            let err = Pipe(); proc.standardError = err
            proc.standardOutput = Pipe()
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw MacTranscriberError.toolFailed("\(URL(fileURLWithPath: exe).lastPathComponent) salió \(proc.terminationStatus): \(e.suffix(300))")
            }
        }.value
    }
}
