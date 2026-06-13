//
//  ActasComponents.swift
//  Transcriber
//
//  Reusable pieces of the Actas dashboard: queue grid, agent health rows,
//  submission rows, and the submit confirmation sheet.
//

import SwiftUI

// MARK: - Queue grid

struct QueueGrid: View {
    let queues: PipelineQueues
    let locks: PipelineLocks?

    private var items: [(String, Int, String, Bool)] {
        [
            ("En cola", queues.inbox.count, "tray.and.arrow.down.fill", locks?.transcriber.isRunning ?? false),
            ("Transcribiendo", (locks?.transcriber.isRunning ?? false) ? queues.inbox.count : 0, "waveform", locks?.transcriber.isRunning ?? false),
            ("Por redactar", queues.transcriptions.count, "text.alignleft", locks?.writer.isRunning ?? false),
            ("Errores", queues.audioErrors.count + queues.textErrors.count, "exclamationmark.triangle.fill", false),
        ]
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items, id: \.0) { item in
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: item.2)
                            .foregroundStyle(item.0 == "Errores" && item.1 > 0 ? .red : .accentColor)
                        if item.3 {
                            ProgressView().controlSize(.mini)
                        }
                        Spacer()
                        Text("\(item.1)")
                            .font(.title2.bold().monospacedDigit())
                    }
                    HStack {
                        Text(item.0).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Agent health

struct AgentRow: View {
    let name: String
    let state: LaunchdState

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(name)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        if state.needsFullDiskAccess { return .orange }
        return state.isHealthy ? .green : .red
    }

    private var statusText: String {
        if state.needsFullDiskAccess { return "Permiso pendiente (FDA)" }
        if !state.loaded { return "No cargado" }
        return state.state
    }
}

// MARK: - Submission row

struct PipelineJobRow: View {
    let job: PipelineJob

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: job.stage.systemImage)
                .foregroundStyle(stageColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName).font(.body).lineLimit(1)
                HStack(spacing: 6) {
                    Text(job.stage.label)
                    if job.transport == .icloud {
                        Image(systemName: "icloud").font(.caption2)
                    }
                    if job.uploadState == .failed {
                        Text("· no enviado").foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if job.stage == .done {
                Button {
                    NotesLinker.open(noteTitled: job.displayName)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
            } else if isActive {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private var isActive: Bool {
        [.transcribing, .redacting].contains(job.stage) || job.uploadState == .uploading
    }

    private var stageColor: Color {
        switch job.stage {
        case .done: return .green
        case .error: return .red
        case .unknown: return .secondary
        default: return .accentColor
        }
    }
}

// MARK: - Submit sheet

struct SubmitSheet: View {
    let pending: PendingImport
    @Binding var submitting: Bool
    @Binding var progress: Double
    let onSubmit: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $name)
                        .autocorrectionDisabled()
                } header: {
                    Text("Título del acta")
                } footer: {
                    Text("Debe coincidir EXACTO con el título de la nota en Apple Notes (carpeta «Actas»). El audio llegará al Mac con este nombre.")
                }
                if submitting {
                    Section {
                        ProgressView(value: progress) {
                            Text("Enviando…")
                        }
                    }
                }
            }
            .navigationTitle("Enviar al Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enviar") {
                        Task { await onSubmit(name.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                    .disabled(submitting || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if name.isEmpty { name = pending.suggestedName } }
        }
        .interactiveDismissDisabled(submitting)
    }
}
