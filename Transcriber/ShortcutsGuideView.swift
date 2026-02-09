//
//  ShortcutsGuideView.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 19/12/25.
//

import SwiftUI

struct ShortcutsGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Transcriber integrates with Siri and the Shortcuts app. Use these actions to automate your transcription workflow.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Available Shortcuts") {
                    ShortcutRow(
                        title: "Transcribe Audio",
                        description: "Transcribes an audio file and returns the text. Perfect for quick transcriptions without saving.",
                        icon: "waveform",
                        color: .blue,
                        phrases: ["Transcribe audio", "Convert audio to text"]
                    )

                    ShortcutRow(
                        title: "Transcribe and Save",
                        description: "Transcribes audio and saves it to your library with a title.",
                        icon: "doc.text",
                        color: .green,
                        phrases: ["Transcribe and save", "Save transcription"]
                    )

                    ShortcutRow(
                        title: "Get Transcriptions",
                        description: "Retrieves your recent transcriptions. Great for reviewing past meetings.",
                        icon: "list.bullet",
                        color: .orange,
                        phrases: ["Get my transcriptions", "Show recent transcriptions"]
                    )

                    ShortcutRow(
                        title: "Search Transcriptions",
                        description: "Searches all your transcriptions for a keyword or phrase.",
                        icon: "magnifyingglass",
                        color: .purple,
                        phrases: ["Search transcriptions", "Find in transcriptions"]
                    )
                }

                Section("Example Automations") {
                    ExampleAutomationRow(
                        title: "Meeting Notes Workflow",
                        steps: [
                            "1. Record meeting with Voice Memos",
                            "2. Share to Transcriber",
                            "3. Get transcription text",
                            "4. Send to Notes or email"
                        ]
                    )

                    ExampleAutomationRow(
                        title: "Daily Voice Journal",
                        steps: [
                            "1. Record voice note each day",
                            "2. Transcribe and save with date",
                            "3. Append to a journal file"
                        ]
                    )

                    ExampleAutomationRow(
                        title: "Interview Transcription",
                        steps: [
                            "1. Import audio file",
                            "2. Transcribe with auto-detect",
                            "3. Export text to document"
                        ]
                    )
                }

                Section {
                    Button {
                        openShortcutsApp()
                    } label: {
                        Label("Open Shortcuts App", systemImage: "arrow.up.forward.app")
                    }
                }
            }
            .navigationTitle("Shortcuts Guide")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func openShortcutsApp() {
        #if os(iOS)
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

struct ShortcutRow: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let phrases: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(color)
                    .cornerRadius(8)

                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Say:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(phrases, id: \.self) { phrase in
                    Text("\"\(phrase)\"")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ExampleAutomationRow: View {
    let title: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(steps, id: \.self) { step in
                Text(step)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ShortcutsGuideView()
}
