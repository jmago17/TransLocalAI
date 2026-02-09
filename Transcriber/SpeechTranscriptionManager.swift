//
//  SpeechTranscriptionManager.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
//

import Foundation
import Speech
import AVFoundation

enum TranscriptionMode {
    case standard
    case speakerIdentification
}

@MainActor
@Observable
class SpeechTranscriptionManager {
    var isTranscribing = false
    var transcriptionProgress: Double = 0

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Transcription

    func transcribe(audioURL: URL, language: String = "en-US") async throws -> String {
        let locale = Locale(identifier: language)

        isTranscribing = true
        transcriptionProgress = 0

        defer {
            isTranscribing = false
            transcriptionProgress = 0
        }

        return try await transcribeWithSpeechAnalyzer(audioURL: audioURL, locale: locale)
    }

    // MARK: - SpeechAnalyzer Implementation

    private func transcribeWithSpeechAnalyzer(audioURL: URL, locale: Locale) async throws -> String {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        // Download language model if needed
        let installedLocales = await SpeechTranscriber.installedLocales
        let isInstalled = installedLocales.contains { $0.identifier == locale.identifier }

        if !isInstalled {
            if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await downloader.downloadAndInstall()
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let transcriptionFuture: String = {
            var fullText = ""
            for try await result in transcriber.results {
                if result.isFinal {
                    let plainText = String(result.text.characters)
                    fullText += plainText + " "
                }
                await MainActor.run {
                    self.transcriptionProgress = min(0.95, self.transcriptionProgress + 0.01)
                }
            }
            return fullText.trimmingCharacters(in: .whitespaces)
        }()

        let audioFile = try AVAudioFile(forReading: audioURL)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        }

        let result = try await transcriptionFuture

        await MainActor.run {
            self.transcriptionProgress = 1.0
        }

        return result
    }

    // MARK: - Language Detection

    func detectLanguage(audioURL: URL) async throws -> String {
        let candidateLocales = [Locale(identifier: "en-US"), Locale(identifier: "es-ES")]
        var bestLanguage = "en-US"
        var bestScore: Int = 0

        let trimmedURL = try await trimAudioForDetection(audioURL: audioURL)
        let shouldCleanup = (trimmedURL != audioURL)

        defer {
            if shouldCleanup {
                try? FileManager.default.removeItem(at: trimmedURL)
            }
        }

        for locale in candidateLocales {
            let score = try await scoreLocale(locale, audioURL: trimmedURL)
            if score > bestScore {
                bestScore = score
                bestLanguage = locale.identifier
            }
        }

        return bestLanguage
    }

    private func scoreLocale(_ locale: Locale, audioURL: URL) async throws -> Int {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )

        // Skip locales whose model isn't installed (don't download just for detection)
        let installedLocales = await SpeechTranscriber.installedLocales
        guard installedLocales.contains(where: { $0.identifier == locale.identifier }) else {
            return 0
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let textFuture: String = {
            var fullText = ""
            for try await result in transcriber.results {
                if result.isFinal {
                    fullText += String(result.text.characters) + " "
                }
            }
            return fullText.trimmingCharacters(in: .whitespaces)
        }()

        let audioFile = try AVAudioFile(forReading: audioURL)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        }

        let text = try await textFuture
        let wordCount = text.split(separator: " ").count
        return wordCount * 100
    }

    // MARK: - Helpers

    private func trimAudioForDetection(audioURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration).seconds

        if duration <= 10 {
            return audioURL
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return audioURL
        }

        let timeRange = CMTimeRange(start: .zero, end: CMTime(seconds: 10, preferredTimescale: 600))
        exportSession.timeRange = timeRange

        let trimmedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("detect-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: trimmedURL)

        try await exportSession.export(to: trimmedURL, as: .m4a)
        return trimmedURL
    }

    static var supportedLanguages: [(code: String, name: String)] {
        [
            ("en-US", "English (US)"),
            ("es-ES", "Spanish (Spain)")
        ]
    }
}

enum TranscriptionError: LocalizedError {
    case languageNotSupported
    case recognizerNotAvailable
    case noAudioFile
    case speechRecognitionFailed(String)
    case audioProcessingFailed
    case noTranscriptionReceived

    var errorDescription: String? {
        switch self {
        case .languageNotSupported:
            return "Speech recognition is not supported for this language on this device."
        case .recognizerNotAvailable:
            return "Speech recognizer is currently not available."
        case .noAudioFile:
            return "No audio file found to transcribe."
        case .speechRecognitionFailed(let message):
            return "Speech recognition failed: \(message)"
        case .audioProcessingFailed:
            return "Failed to process audio file. The file may be corrupted or in an unsupported format."
        case .noTranscriptionReceived:
            return "No transcription was generated. The audio may not contain recognizable speech, or the language model may not be downloaded."
        }
    }
}
