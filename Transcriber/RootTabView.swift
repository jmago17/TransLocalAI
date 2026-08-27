//
//  RootTabView.swift
//  Transcriber
//
//  Device-local app root for iPhone and iPad.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var selectedTab = 0
    private var recorder: AudioRecorderManager { AudioRecorderManager.shared }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "books.vertical.fill", value: 0) {
                ContentView()
            }
            Tab("Record", systemImage: "mic.fill", value: 1) {
                RecordTabView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: 2) {
                LocalSettingsView()
            }
        }
        .liquidCrystalScreen()
        // Recording started from outside the app (Sidenotes deep link,
        // Shortcut/Intent) — jump to where it's actually visible instead of
        // leaving it running silently behind the Library tab.
        .onChange(of: recorder.isRecording) { _, isRecording in
            if isRecording { selectedTab = 1 }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Transcription.self, inMemory: true)
}
