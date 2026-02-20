//
//  ShareTranscriptionManager.swift
//  TranscriberShare
//
//  Created by Josu Martinez Gonzalez on 19/12/25.
//

import Foundation
import Speech

class ShareTranscriptionManager {
    private let hybridService = HybridTranscriptionService()

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func detectLanguage(audioURL: URL) async throws -> String {
        return try await hybridService.detectLanguage(audioURL: audioURL)
    }

    func transcribe(audioURL: URL, language: String) async throws -> String {
        try await hybridService.prepareModelIfNeeded(language: language, progress: nil)
        let result = try await hybridService.transcribe(audioURL: audioURL, language: language)
        return result.text
    }
}
