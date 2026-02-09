//
//  TranscribeAndSaveIntent.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
//

import AppIntents
import SwiftUI
import Speech
import SwiftData
import AVFoundation
import Foundation

struct TranscribeAndSaveIntent: AppIntent {
    static var title: LocalizedStringResource = "Transcribe and Save"
    static var description = IntentDescription("Transcribes an audio file and saves it to your Transcriber library.")
    
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true
    
    @Parameter(title: "Audio File", description: "The audio file to transcribe")
    var audioFile: IntentFile
    
    @Parameter(title: "Title", 
               description: "Optional title for the transcription",
               default: "Shortcut Transcription")
    var title: String
    
    @Parameter(title: "Auto-detect Language",
               description: "Automatically detect the language",
               default: true)
    var autoDetect: Bool
    
    @Parameter(title: "Language", 
               description: "The language of the audio (if not auto-detecting)",
               default: "en-US")
    var language: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Transcribe \(\.$audioFile) as \(\.$title)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Request speech recognition permission if needed
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        
        if authStatus == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            
            if !granted {
                throw TranscribeError.permissionDenied
            }
        } else if authStatus != .authorized {
            throw TranscribeError.permissionDenied
        }
        
        // Get documents directory for saving audio file
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Use original filename if available, otherwise use title
        let originalFilename = audioFile.filename
        let cleanFilename = originalFilename.replacingOccurrences(of: " ", with: "-")
        let timestamp = Date().timeIntervalSince1970
        let savedAudioURL = documentsDirectory.appendingPathComponent("\(cleanFilename)-\(Int(timestamp)).m4a")
        
        // Save the audio file permanently
        try audioFile.data.write(to: savedAudioURL)
        
        // Create temporary file for transcription
        let temporaryFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp-transcribe.m4a")
        try audioFile.data.write(to: temporaryFileURL)
        
        defer {
            try? FileManager.default.removeItem(at: temporaryFileURL)
        }
        
        let hybridService = HybridTranscriptionService()
        
        // Transcribe the audio
        do {
            var languageToUse = language
            
            if autoDetect {
                do {
                    languageToUse = try await hybridService.detectLanguage(audioURL: temporaryFileURL, preferApple: true)
                } catch {
                    languageToUse = language
                }
            }

            try await hybridService.prepareModelIfNeeded(language: languageToUse, progress: nil)
            
            let result = try await hybridService.transcribe(audioURL: temporaryFileURL, language: languageToUse)
            let transcriptionText = result.text
            let duration = result.duration
            
            // Save to SwiftData
            let schema = Schema([Transcription.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            let modelContext = modelContainer.mainContext
            
            let transcription = Transcription(
                title: title,
                transcriptionText: transcriptionText,
                language: languageToUse,
                duration: duration,
                audioFileURL: savedAudioURL.lastPathComponent,
                engineUsed: (result.engineUsed == .appleSpeech ? "apple" : "whisper")
            )
            
            modelContext.insert(transcription)
            try modelContext.save()
            
            return .result(
                dialog: "Successfully transcribed and saved '\(title)' to your library."
            )
            
        } catch {
            // Clean up audio file if transcription failed
            try? FileManager.default.removeItem(at: savedAudioURL)
            throw TranscribeError.transcriptionFailed(error.localizedDescription)
        }
    }
}

enum TranscribeError: Error, LocalizedError {
    case permissionDenied
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission is required."
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}
