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
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var title: String = ""
    var transcriptionText: String = ""
    var language: String = "en-US"
    var duration: TimeInterval = 0
    var audioFileURL: String? // Store filename of audio file (resolved via AudioFileManager)
    var engineUsed: String = ""
    
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

