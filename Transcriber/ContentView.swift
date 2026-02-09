//
//  ContentView.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
//

// TODO: [Arquitectura] Integrar motor híbrido (Apple Speech + WhisperKit)
// - Crear protocolo `TranscriptionEngine` con APIs async: detectLanguage(audioURL:), transcribe(audioURL:language:)
// - Implementar `AppleSpeechEngine` (motor principal) y `WhisperKitEngine` (fallback)
// - Implementar `HybridTranscriptionService` que seleccione motor según idioma/soporte
// - Soporte para euskera (eu-ES) usando WhisperKit automáticamente
// - Diseño modular y testeable (inyección de dependencias)
// - Añadir pruebas del split/merge y del selector de motor
// TODO: [Descargas] Gestión de modelo Whisper bajo demanda
// - `WhisperModelManager` descarga modelos cuando se necesiten (no en el bundle)
// - Guardar modelos en Application Support y reutilizarlos
// - Comprobar integridad/tamaño/versión y caché con invalidación
// - Exponer progreso/cancelación de descarga
// TODO: [Integración] Modificar puntos de entrada de transcripción
// - `ImportAudioView` y `TranscribeAndSaveIntent` deben usar `HybridTranscriptionService`
// - Mantener 100% offline una vez descargado el modelo
// - Manejar errores y timeouts de forma robusta (memoria y rendimiento en iPhone)
// TODO: [UI/UX] Indicadores y controles
// - Mostrar estado de descarga del modelo Whisper y tamaño aproximado
// - Permitir pre-descarga desde ajustes (futuro)
// - Mostrar qué motor se usó en cada transcripción

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transcription.timestamp, order: .reverse) private var transcriptions: [Transcription]
    
    @State private var showImportView = false
    @State private var showShortcutsGuide = false
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            Group {
                if filteredTranscriptions.isEmpty {
                    emptyStateView
                } else {
                    transcriptionsList
                }
            }
            .navigationTitle("Transcriptions")
            .searchable(text: $searchText, prompt: "Search transcriptions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showImportView = true }) {
                        Label("Import Audio", systemImage: "plus.circle.fill")
                    }
                }

#if os(iOS)
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button(action: { showShortcutsGuide = true }) {
                            Label("Shortcuts Guide", systemImage: "shortcuts")
                        }
                        EditButton()
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
#else
                ToolbarItem(placement: .secondaryAction) {
                    Button(action: { showShortcutsGuide = true }) {
                        Label("Shortcuts Guide", systemImage: "shortcuts")
                    }
                }
#endif
            }
            .sheet(isPresented: $showImportView) {
                ImportAudioView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showShortcutsGuide) {
                ShortcutsGuideView()
            }
        } detail: {
            ContentUnavailableView(
                "Select a Transcription",
                systemImage: "text.bubble",
                description: Text("Choose a transcription from the list to view its details")
            )
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Transcriptions", systemImage: "waveform")
        } description: {
            Text("Import audio files to create transcriptions")
        } actions: {
            Button(action: { showImportView = true }) {
                Label("Import Audio File", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var transcriptionsList: some View {
        List {
            ForEach(filteredTranscriptions) { transcription in
                NavigationLink {
                    TranscriptionDetailView(transcription: transcription)
                } label: {
                    TranscriptionRowView(transcription: transcription)
                }
            }
            .onDelete(perform: deleteTranscriptions)
        }
    }
    
    private var filteredTranscriptions: [Transcription] {
        if searchText.isEmpty {
            return transcriptions
        } else {
            return transcriptions.filter { transcription in
                transcription.title.localizedCaseInsensitiveContains(searchText) ||
                transcription.transcriptionText.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func deleteTranscriptions(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let transcription = filteredTranscriptions[index]
                
                // TODO: Si en el futuro guardamos artefactos de Whisper por transcripción, limpiarlos aquí si aplica
                // Delete associated audio file if it exists
                if let audioFileName = transcription.audioFileURL {
                    let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let audioURL = documentsDirectory.appendingPathComponent(audioFileName)
                    try? FileManager.default.removeItem(at: audioURL)
                }
                
                modelContext.delete(transcription)
            }
        }
    }
}

import AVFoundation

struct TranscriptionRowView: View {
    let transcription: Transcription
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(transcription.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: languageIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let badge = engineBadge {
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(4)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(transcription.transcriptionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            HStack {
                Label(formatDuration(transcription.duration), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                Text(transcription.timestamp, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // TODO: Mostrar motor usado (Apple/Whisper) en la fila si está disponible en el modelo
    private var languageIcon: String {
        if transcription.language.hasPrefix("es") {
            return "flag.fill"
        } else {
            return "flag.fill"
        }
    }
    
    private var engineBadge: String? {
        switch transcription.engineUsed.lowercased() {
        case "apple": return "Apple"
        case "whisper": return "Whisper"
        default: return nil
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Transcription.self, inMemory: true)
}

