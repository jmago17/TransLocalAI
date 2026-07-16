//
//  RootTabView.swift
//  Transcriber
//
//  Device-local app root for iPhone and iPad.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Library", systemImage: "books.vertical.fill") {
                ContentView()
            }
            Tab("Record", systemImage: "mic.fill") {
                RecordTabView()
            }
            Tab("Settings", systemImage: "gearshape.fill") {
                LocalSettingsView()
            }
        }
        .liquidCrystalScreen()
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Transcription.self, inMemory: true)
}
