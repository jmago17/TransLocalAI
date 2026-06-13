//
//  RootTabView.swift
//  Transcriber
//
//  App root. Splits the app into the Mac-backed "Actas" pipeline, the local
//  transcription library, recording, and settings. The PipelineController is
//  created once here and shared down via the environment.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var controller = PipelineController()

    var body: some View {
        TabView {
            Tab("Actas", systemImage: "doc.text.fill") {
                ActasView()
            }
            Tab("Biblioteca", systemImage: "books.vertical.fill") {
                ContentView()
            }
            Tab("Grabar", systemImage: "mic.fill") {
                RecordTabView()
            }
            Tab("Ajustes", systemImage: "gearshape.fill") {
                ActasSettingsView()
            }
        }
        .environment(controller)
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Transcription.self, PipelineJob.self], inMemory: true)
}
