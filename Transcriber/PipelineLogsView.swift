//
//  PipelineLogsView.swift
//  Transcriber
//
//  Live tail of the pipeline's log streams (whisper, redactor, watchers,
//  control). Reads from /api/logs and refreshes on demand.
//

import SwiftUI

struct PipelineLogsView: View {
    @Environment(PipelineController.self) private var controller

    private let streams: [(id: String, label: String)] = [
        ("whisper", "Whisper"),
        ("writer", "Redactor"),
        ("watchInbox", "Watch Inbox"),
        ("watchTranscriptions", "Watch Transcripciones"),
        ("control", "Control"),
    ]

    @State private var selected = "whisper"
    @State private var lines: [String] = []
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Stream", selection: $selected) {
                ForEach(streams, id: \.id) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(idx)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: lines.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if loading { ProgressView() } else {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .onChange(of: selected) { _, _ in Task { await load() } }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            lines = try await ActasServerClient.shared.logs(stream: selected, limit: 300)
        } catch {
            lines = ["⚠️ \(error.localizedDescription)"]
        }
    }
}
