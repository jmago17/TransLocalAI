//
//  ActasTranscriptionsView.swift
//  Transcriber
//
//  Browse the transcriptions produced on the Mac (whisper output): those still
//  pending redaction and those already turned into actas. Tap one to read the
//  full text fetched from the server.
//

import SwiftUI

struct ActasTranscriptionsView: View {
    @Environment(PipelineController.self) private var controller

    var body: some View {
        List {
            if let list = controller.transcriptions {
                if !list.processing.isEmpty {
                    Section("Por redactar") {
                        ForEach(list.processing) { file in
                            NavigationLink(file.baseName) {
                                MacTranscriptionDetailView(name: file.name)
                            }
                        }
                    }
                }
                Section("Hechas (acta en Notas)") {
                    if list.done.isEmpty {
                        Text("Nada todavía").foregroundStyle(.secondary)
                    }
                    ForEach(list.done) { file in
                        NavigationLink {
                            MacTranscriptionDetailView(name: file.name)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(file.baseName)
                                if let d = file.modifiedDate {
                                    Text(d, format: .relative(presentation: .named))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Sin datos", systemImage: "text.alignleft",
                                       description: Text("Conéctate al Mac para ver las transcripciones."))
            }
        }
        .navigationTitle("Transcripciones")
        .refreshable { await controller.refresh(logs: false) }
    }
}

struct MacTranscriptionDetailView: View {
    let name: String
    @State private var detail: TranscriptionDetail?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().padding()
            } else if let detail {
                Text(detail.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            } else if let error {
                ContentUnavailableView("No se pudo cargar", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            }
        }
        .navigationTitle((name as NSString).deletingPathExtension)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let detail {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = detail.text
                        #endif
                    } label: { Image(systemName: "doc.on.doc") }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            detail = try await ActasServerClient.shared.transcription(name: name)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif
