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
    /// The language the transcription actually ran with (BCP-47, or
    /// "multilingual"/"unknown"). This is the resolved language, i.e. the
    /// detected one when auto-detect was used.
    var language: String = "en-US"
    /// Whether the language above was chosen by auto-detection rather than
    /// picked by the user. Defaults false (safe lightweight migration).
    var languageWasAutoDetected: Bool = false
    var duration: TimeInterval = 0
    var audioFileURL: String? // Store filename of audio file (resolved via AudioFileManager)
    var engineUsed: String = ""
    var meetingNotes: String = ""

    init(
        timestamp: Date = Date(),
        title: String = "",
        transcriptionText: String = "",
        language: String = "en-US",
        languageWasAutoDetected: Bool = false,
        duration: TimeInterval = 0,
        audioFileURL: String? = nil,
        engineUsed: String = "apple",
        meetingNotes: String = ""
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.title = title.isEmpty ? "Transcription \(timestamp.formatted(date: .abbreviated, time: .shortened))" : title
        self.transcriptionText = transcriptionText
        self.language = language
        self.languageWasAutoDetected = languageWasAutoDetected
        self.duration = duration
        self.audioFileURL = audioFileURL
        self.engineUsed = engineUsed
        self.meetingNotes = meetingNotes
    }
}
