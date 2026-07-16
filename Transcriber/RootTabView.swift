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
            Tab("Biblioteca", systemImage: "books.vertical.fill") {
                ContentView()
            }
            Tab("Grabar", systemImage: "mic.fill") {
                RecordTabView()
            }
            Tab("Ajustes", systemImage: "gearshape.fill") {
                LocalSettingsView()
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Transcription.self, inMemory: true)
}
