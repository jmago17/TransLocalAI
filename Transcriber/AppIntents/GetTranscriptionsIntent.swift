//
//  GetTranscriptionsIntent.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 19/12/25.
//

import AppIntents
import SwiftData

/// Gets recent transcriptions from the library
struct GetTranscriptionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Transcriptions"
    static var description = IntentDescription("Gets your recent transcriptions from the Transcriber library.")

    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    @Parameter(title: "Limit",
               description: "Maximum number of transcriptions to return",
               default: 5)
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Get last \(\.$limit) transcriptions")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let schema = Schema([Transcription.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = modelContainer.mainContext

        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        let transcriptions = try context.fetch(descriptor)

        let results = transcriptions.map { t in
            "[\(t.title)] \(t.transcriptionText.prefix(200))..."
        }

        return .result(value: results)
    }
}
