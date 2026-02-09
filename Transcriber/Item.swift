//
//  Item.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
//

import Foundation
import SwiftData

@Model
final class Transcription {
    var id: UUID
    var timestamp: Date
    var title: String
    var transcriptionText: String
    var language: String // "es-ES" or "en-US"
    var duration: TimeInterval
    var audioFileURL: String? // Store relative path to audio file
    var engineUsed: String // "apple" or "whisper"
    
    init(
        timestamp: Date = Date(),
        title: String = "",
        transcriptionText: String = "",
        language: String = "en-US",
        duration: TimeInterval = 0,
        audioFileURL: String? = nil,
        engineUsed: String = "apple"
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.title = title.isEmpty ? "Transcription \(timestamp.formatted(date: .abbreviated, time: .shortened))" : title
        self.transcriptionText = transcriptionText
        self.language = language
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.engineUsed = engineUsed
    }
}

