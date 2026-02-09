//
//  TranscriberShortcuts.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 19/12/25.
//

import AppIntents

/// Provides pre-built shortcuts that appear in the Shortcuts app
struct TranscriberShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranscribeOnlyIntent(),
            phrases: [
                "Transcribe audio with \(.applicationName)",
                "Convert audio to text with \(.applicationName)",
                "Transcribe this with \(.applicationName)"
            ],
            shortTitle: "Transcribe Audio",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: TranscribeAndSaveIntent(),
            phrases: [
                "Transcribe and save with \(.applicationName)",
                "Save transcription with \(.applicationName)",
                "Transcribe meeting with \(.applicationName)"
            ],
            shortTitle: "Transcribe & Save",
            systemImageName: "doc.text"
        )

        AppShortcut(
            intent: GetTranscriptionsIntent(),
            phrases: [
                "Get my transcriptions from \(.applicationName)",
                "Show recent transcriptions in \(.applicationName)",
                "What did I transcribe in \(.applicationName)"
            ],
            shortTitle: "Get Transcriptions",
            systemImageName: "list.bullet"
        )

        AppShortcut(
            intent: SearchTranscriptionsIntent(),
            phrases: [
                "Search transcriptions in \(.applicationName)",
                "Find in transcriptions with \(.applicationName)",
                "Look up transcription in \(.applicationName)"
            ],
            shortTitle: "Search Transcriptions",
            systemImageName: "magnifyingglass"
        )
    }
}
