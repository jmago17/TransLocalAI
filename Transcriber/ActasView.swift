//
//  ActasView.swift
//  Transcriber
//
//  The heart of the app: the live view of the Mac's actas pipeline. Shows
//  reachability, queue state, agent health, the audios this device submitted
//  (with their derived stage), and entry points to the Mac's transcriptions and
//  logs. Submitting an audio uploads it (HTTP, iCloud fallback) into the pipeline.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ActasView: View {
    @Environment(PipelineController.self) private var controller
    @Environment(\.modelContext) private var context
    @Query(sort: \PipelineJob.createdAt, order: .reverse) private var jobs: [PipelineJob]

    @State private var showingImporter = false
    @State private var pendingImport: PendingImport?
    @State private var submitting = false
    @State private var submitProgress: Double = 0

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                if controller.isReachable {
                    queueSection
                    agentsSection
                    macLinksSection
                }
                submissionsSection
            }
            .navigationTitle("Actas")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Enviar audio al Mac", systemImage: "square.and.arrow.up")
                    }
                    .disabled(submitting)
                }
            }
            .refreshable { await controller.refresh() }
            .task {
                await controller.refresh()
                controller.reconcile(jobs: jobs, context: context)
                controller.startObservingEvents {
                    await controller.refresh(logs: false)
                    controller.reconcile(jobs: jobs, context: context)
                }
            }
            .onChange(of: controller.status) { _, _ in
                controller.reconcile(jobs: jobs, context: context)
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav, .aiff],
                          allowsMultipleSelection: false) { handleImport($0) }
            .sheet(item: $pendingImport) { item in
                SubmitSheet(pending: item,
                            submitting: $submitting,
                            progress: $submitProgress) { name in
                    await submit(item: item, displayName: name)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var connectionSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: bannerIcon)
                    .font(.title2)
                    .foregroundStyle(bannerColor)
                VStack(alignment: .leading) {
                    Text(bannerTitle).font(.headline)
                    if let subtitle = bannerSubtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                Spacer()
                if controller.isRefreshing { ProgressView() }
            }
        }
    }

    private var fdaPending: Bool { controller.isReachable && !controller.fsAccessible }

    private var bannerIcon: String {
        if fdaPending { return "exclamationmark.lock.fill" }
        return controller.isReachable ? "wifi" : "wifi.slash"
    }
    private var bannerColor: Color {
        if fdaPending { return .orange }
        return controller.isReachable ? .green : .orange
    }
    private var bannerTitle: String {
        if fdaPending { return "El Mac no puede leer Reuniones" }
        return controller.isReachable ? "Conectado al Mac" : "Sin conexión con el Mac"
    }
    private var bannerSubtitle: String? {
        if fdaPending {
            return "Concede «Acceso completo al disco» al servidor de actas en el Mac (Ajustes → Privacidad)."
        }
        if let err = controller.lastError { return err }
        if !controller.isReachable { return "Se usará iCloud como respaldo al enviar." }
        return nil
    }

    @ViewBuilder
    private var queueSection: some View {
        if let q = controller.status?.queues {
            Section("Cola") {
                QueueGrid(queues: q, locks: controller.status?.locks)
            }
        }
    }

    @ViewBuilder
    private var agentsSection: some View {
        if let l = controller.status?.launchd {
            Section("Agentes") {
                AgentRow(name: "Transcriptor", state: l.transcriber)
                AgentRow(name: "Redactor", state: l.writer)
                AgentRow(name: "Control", state: l.control)
            }
        }
    }

    private var macLinksSection: some View {
        Section {
            NavigationLink {
                ActasTranscriptionsView()
            } label: {
                Label("Transcripciones del Mac", systemImage: "text.alignleft")
            }
            NavigationLink {
                PipelineLogsView()
            } label: {
                Label("Logs en vivo", systemImage: "terminal")
            }
        }
    }

    @ViewBuilder
    private var submissionsSection: some View {
        if !jobs.isEmpty {
            Section("Mis envíos") {
                ForEach(jobs) { job in
                    PipelineJobRow(job: job)
                        .swipeActions {
                            Button("Borrar", role: .destructive) {
                                context.delete(job)
                            }
                        }
                }
            }
        }
    }

    // MARK: - Import + submit

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        // Copy out of the security scope into a temp file we control.
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tmp)
        do {
            try FileManager.default.copyItem(at: url, to: tmp)
            let base = (url.lastPathComponent as NSString).deletingPathExtension
            pendingImport = PendingImport(url: tmp, suggestedName: base)
        } catch {
            controller.lastError = "No se pudo leer el audio: \(error.localizedDescription)"
        }
    }

    private func submit(item: PendingImport, displayName: String) async {
        submitting = true
        submitProgress = 0
        defer { submitting = false }
        await controller.submit(
            audioURL: item.url,
            displayName: displayName,
            source: .imported,
            audioFileName: nil,
            context: context,
            onProgress: { p in Task { @MainActor in submitProgress = p } }
        )
        controller.reconcile(jobs: jobs, context: context)
        pendingImport = nil
    }
}

/// A picked audio waiting for the user to confirm its name (= Apple Notes title).
struct PendingImport: Identifiable {
    let id = UUID()
    let url: URL
    let suggestedName: String
}
