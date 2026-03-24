//
//  SearchTranscriptionsIntent.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 19/12/25.
//

import AppIntents
import SwiftData

/// Searches transcriptions for a keyword
struct SearchTranscriptionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Transcriptions"
    static var description = IntentDescription("Searches your transcriptions for a keyword or phrase.")

    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    @Parameter(title: "Search Text",
               description: "The text to search for in your transcriptions")
    var searchText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search transcriptions for \(\.$searchText)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let schema = Schema([Transcription.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        let transcriptions = try context.fetch(descriptor)

        let matches = transcriptions.filter { t in
            t.title.localizedCaseInsensitiveContains(searchText) ||
            t.transcriptionText.localizedCaseInsensitiveContains(searchText)
        }

        let results = matches.prefix(10).map { t in
            "[\(t.title)] \(t.transcriptionText.prefix(150))..."
        }

        return .result(value: Array(results))
    }
}
