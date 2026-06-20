//
//  TranscriberMacApp.swift
//  TranscriberMac
//
//  Menu bar companion app: runs in the background, picks up audios submitted
//  from iOS via CloudKit, transcribes + drafts the acta locally, and writes it
//  to Apple Notes. Replaces the launchd `actas-server` + agents path.
//

import SwiftUI
import SwiftData

@main
struct TranscriberMacApp: App {
    var sharedModelContainer: ModelContainer = {
        // Same SwiftData + CloudKit schema as iOS, so PipelineJob records and
        // the Transcription library sync across devices through CloudKit.
        let schema = Schema([Transcription.self, PipelineJob.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .modelContainer(sharedModelContainer)
        } label: {
            Image(systemName: "doc.text.fill")
        }
        .menuBarExtraStyle(.window)

        Window("TransLocalAI", id: "main") {
            MacMainView()
                .modelContainer(sharedModelContainer)
        }
        .windowResizability(.contentSize)

        Settings {
            MacSettingsView()
        }
    }
}
