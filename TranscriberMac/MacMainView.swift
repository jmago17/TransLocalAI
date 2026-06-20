//
//  MacMainView.swift
//  TranscriberMac
//
//  Main window: what's processing now, the queue, and the actas finished today.
//  Mirrors design-mockups/mac-window.html.
//

import SwiftUI
import SwiftData

struct MacMainView: View {
    @Environment(PipelineProcessor.self) private var processor
    @Query(sort: \PipelineJob.createdAt, order: .reverse) private var jobs: [PipelineJob]

    private var queued: [PipelineJob] { jobs.filter { $0.transport == .cloudkit && $0.stage == .queued } }
    private var doneToday: [PipelineJob] {
        jobs.filter { $0.stage == .done && Calendar.current.isDateInToday($0.lastSyncedAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if processor.isRunning { processingSection }
                section("En cola", queued) { job in
                    row(job, icon: "tray.and.arrow.down.fill", color: .accentColor,
                        subtitle: "Esperando") { Text("En cola").badgeStyle() }
                }
                section("Hechas hoy", doneToday) { job in
                    row(job, icon: "checkmark.seal.fill", color: .green,
                        subtitle: engineSubtitle) {
                        Button("Abrir en Notas ↗") { NotesWriter.show(title: job.displayName) }
                            .buttonStyle(.link)
                    }
                }
                if processor.isRunning == false && queued.isEmpty && doneToday.isEmpty {
                    ContentUnavailableView("Todo al día", systemImage: "checkmark.circle",
                        description: Text("No hay audios pendientes. Los nuevos llegan por iCloud."))
                        .padding(.top, 60)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 460)
        .navigationTitle("TransLocalAI")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { processor.tick() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }

    private var engineSubtitle: String {
        MacSettings.shared.redact.label
    }

    @ViewBuilder
    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Procesando ahora").sectionHeader()
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform").foregroundStyle(.tint)
                    Text(processor.currentJobName ?? "").font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                ProgressView().progressViewStyle(.linear)
                Text(processor.currentStageLabel ?? "Procesando…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(15)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 11))
        }
    }

    @ViewBuilder
    private func section<RowContent: View>(_ title: String, _ items: [PipelineJob],
                         @ViewBuilder row: @escaping (PipelineJob) -> RowContent) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).sectionHeader()
                VStack(spacing: 0) {
                    ForEach(items) { job in
                        row(job)
                        if job.id != items.last?.id { Divider() }
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 11))
            }
        }
    }

    private func row(_ job: PipelineJob, icon: String, color: Color, subtitle: String,
                     @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 18)).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.displayName).font(.system(size: 13.5, weight: .semibold))
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

private extension View {
    func sectionHeader() -> some View {
        self.font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary).textCase(.uppercase)
    }
    func badgeStyle() -> some View {
        self.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}
