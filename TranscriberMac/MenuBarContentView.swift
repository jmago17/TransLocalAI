//
//  MenuBarContentView.swift
//  TranscriberMac
//
//  The menu bar popover: pipeline status at a glance, current job, last acta,
//  and quick actions. Mirrors design-mockups/mac-menubar.html.
//

import SwiftUI
import SwiftData

struct MenuBarContentView: View {
    @Environment(PipelineProcessor.self) private var processor
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \PipelineJob.createdAt, order: .reverse) private var jobs: [PipelineJob]

    private var queued: Int { jobs.filter { $0.transport == .cloudkit && $0.stage == .queued }.count }
    private var doneToday: Int {
        jobs.filter { $0.stage == .done && Calendar.current.isDateInToday($0.lastSyncedAt ?? .distantPast) }.count
    }
    private var lastDone: PipelineJob? {
        jobs.first { $0.stage == .done }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stats
            if processor.isRunning { currentJob }
            if let last = lastDone { lastActa(last) }
            Divider()
            footer
        }
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: "doc.text.fill").foregroundStyle(.white).font(.system(size: 14)))
            VStack(alignment: .leading, spacing: 1) {
                Text("TransLocalAI").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(processor.isRunning ? .green : .secondary).frame(width: 7, height: 7)
                    Text(processor.isRunning ? "Procesando" : "En espera")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var stats: some View {
        HStack(spacing: 8) {
            stat("\(queued)", "En cola", highlight: false)
            stat(processor.isRunning ? "1" : "0", "Procesando", highlight: processor.isRunning)
            stat("\(doneToday)", "Hechas hoy", highlight: false)
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
    }

    private func stat(_ n: String, _ label: String, highlight: Bool) -> some View {
        VStack(spacing: 1) {
            Text(n).font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(highlight ? Color.accentColor : .primary)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(highlight ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private var currentJob: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(.tint)
                Text(processor.currentJobName ?? "")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            ProgressView().progressViewStyle(.linear).controlSize(.small)
            Text(processor.currentStageLabel ?? "Procesando…")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 11))
        .padding(.horizontal, 12).padding(.bottom, 10)
    }

    private func lastActa(_ job: PipelineJob) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 1) {
                Text(job.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("Acta lista").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { NotesWriter.show(title: job.displayName) } label: {
                Image(systemName: "arrow.up.forward.app")
            }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            menuRow("Abrir ventana", "macwindow") {
                openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
            }
            if let err = processor.lastError {
                Text(err).font(.system(size: 11)).foregroundStyle(.red)
                    .lineLimit(2).padding(.horizontal, 12).padding(.vertical, 4)
            }
            menuRow("Salir", "power") { NSApplication.shared.terminate(nil) }
        }
        .padding(6)
    }

    private func menuRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
