//
//  RootTabView.swift
//  Transcriber
//
//  Device-local app root for iPhone and iPad.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
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
            if isRecording {
                selectedTab = 1
            } else {
                // Covers stops that nobody saved: the system ending capture
                // (call, media reset, encode error) or a stop intent that
                // died before writing its entry.
                RecordingRecovery.recover(into: modelContext)
            }
        }
        .onAppear {
            // Recordings cut short by the app being killed or crashing.
            RecordingRecovery.recover(into: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { RecordingRecovery.recover(into: modelContext) }
        }
        .alert(
            "Recording Stopped",
            isPresented: Binding(
                get: { recorder.systemStopMessage != nil },
                set: { if !$0 { recorder.systemStopMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { recorder.systemStopMessage = nil }
        } message: {
            Text(recorder.systemStopMessage ?? "")
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Transcription.self, inMemory: true)
}
