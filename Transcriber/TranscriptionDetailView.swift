//
//  TranscriptionDetailView.swift
//  Transcriber
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

struct TranscriptionDetailView: View {
    @Bindable var transcription: Transcription
    @State private var isEditing = false

    @State private var isGeneratingNotes = false
    @State private var generatedNotes: String?
    @State private var showNotes = false
    @State private var showPromptCustomization = false
    @State private var progressMessage = "Generating notes..."
    @State private var canMergeNotes = false  // True when notes are in parts and can be merged
    @State private var rawChunkSummaries: [String] = []  // Store raw summaries for merging
    @State private var isMerging = false

    private let defaultPrompt = """
    provide detailed notes for the following meeting:

    1. Summary:
     • Briefly summarize the main topics discussed during the meeting.
     • Highlight any key decisions or outcomes reached.
    2. Important Bullet Point List:
     • List the key topics covered in the meeting.
     • Note any significant discussions or points raised by participants.
     • Highlight major decisions or actions agreed upon.
    3. Cited Tasks:
     • Detail all tasks assigned to each participant.
     • Specify deadlines and responsibilities for each task.
     • Ensure that all tasks are clearly cited and linked back to specific actions taken during the meeting.

    Please ensure that the notes are clear, concise, and organized to facilitate easy reference and follow-up actions.
    """

    @State private var customPrompt: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Generate Meeting Notes Section - AT THE TOP
                if #available(iOS 26, macOS 26, *) {
                    VStack(spacing: 12) {
                        Button {
                            isGeneratingNotes = true
                            generatedNotes = nil
                            progressMessage = "Generating notes..."
                            showNotes = true
                            Task {
                                await generateMeetingNotes()
                            }
                        } label: {
                            Label("Generate Meeting Notes", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(transcription.transcriptionText.isEmpty)

                        Button {
                            withAnimation {
                                showPromptCustomization.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Customize Prompt")
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: showPromptCustomization ? "chevron.up" : "chevron.down")
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        if showPromptCustomization {
                            VStack(alignment: .leading, spacing: 8) {
                                TextEditor(text: $customPrompt)
                                    .frame(minHeight: 150)
                                    .padding(8)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                                    .font(.caption)

                                Button("Restore Default") {
                                    customPrompt = defaultPrompt
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }

                // Metadata section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            transcription.language == "multilingual" ? "Multilingual" : transcription.language,
                            systemImage: "globe"
                        )
                        Spacer()
                        Label(formatDuration(transcription.duration), systemImage: "clock")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Text(transcription.timestamp, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // Title
                if isEditing {
                    TextField("Title", text: $transcription.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(transcription.title)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Divider()

                // Transcription text
                if isEditing {
                    TextEditor(text: $transcription.transcriptionText)
                        .frame(minHeight: 300)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                } else {
                    Text(transcription.transcriptionText.isEmpty ? "No transcription available" : transcription.transcriptionText)
                        .textSelection(.enabled)
                        .font(.body)
                }

                Spacer()
            }
            .padding()
        }
        .onAppear {
            if customPrompt.isEmpty {
                customPrompt = defaultPrompt
            }
        }
        .navigationTitle("Transcription")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    if !transcription.transcriptionText.isEmpty {
                        ShareLink(item: transcription.transcriptionText) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    Button(isEditing ? "Done" : "Edit") {
                        isEditing.toggle()
                    }
                }
            }
        }
        .sheet(isPresented: $showNotes) {
            NavigationStack {
                ScrollView {
                    if isGeneratingNotes {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text(progressMessage)
                                .font(.headline)
                            Text("This may take a moment for long transcriptions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .padding()
                    } else if let notes = generatedNotes {
                        VStack(alignment: .leading, spacing: 16) {
                            // Action buttons at the top
                            HStack {
                                ShareLink(item: notes) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    UIPasteboard.general.string = notes
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)

                                #if os(iOS)
                                Button {
                                    printNotes(notes)
                                } label: {
                                    Label("Print", systemImage: "printer")
                                }
                                .buttonStyle(.bordered)
                                #endif
                            }

                            // Show merge button if notes are in parts
                            if canMergeNotes && !isMerging {
                                if #available(iOS 26, macOS 26, *) {
                                    Button {
                                        isMerging = true
                                        Task {
                                            await mergeNotes()
                                        }
                                    } label: {
                                        Label("Merge into Single Summary", systemImage: "arrow.triangle.merge")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                }
                            }

                            if isMerging {
                                HStack {
                                    ProgressView()
                                    Text("Merging summaries...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }

                            Divider()

                            Text(notes)
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                }
                .navigationTitle("Meeting Notes")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showNotes = false }
                    }
                }
            }
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

    #if os(iOS)
    private func printNotes(_ notes: String) {
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName = "Meeting Notes"
        printController.printInfo = printInfo

        let formatter = UISimpleTextPrintFormatter(text: notes)
        formatter.perPageContentInsets = UIEdgeInsets(top: 72, left: 72, bottom: 72, right: 72)
        printController.printFormatter = formatter

        printController.present(animated: true)
    }
    #endif

    @available(iOS 26, macOS 26, *)
    private func generateMeetingNotes() async {
        #if canImport(FoundationModels)
        // Reset merge state
        await MainActor.run {
            canMergeNotes = false
            rawChunkSummaries = []
        }

        do {
            let transcript = transcription.transcriptionText

            // On-device model has limited context (~4000 tokens ≈ ~8000 chars with prompt)
            // Use smaller chunks to be safe
            let maxChunkSize = 6000

            if transcript.count <= maxChunkSize {
                // Short enough - process directly
                await MainActor.run { progressMessage = "Analyzing transcript..." }
                let session = LanguageModelSession()
                let input = "\(customPrompt)\n\nMeeting Transcript:\n\(transcript)"
                let response = try await session.respond(to: input)
                generatedNotes = response.content
            } else {
                // Long transcript - summarize in chunks then combine
                var chunkSummaries: [String] = []
                let chunks = splitIntoChunks(text: transcript, maxSize: maxChunkSize)

                for (index, chunk) in chunks.enumerated() {
                    await MainActor.run {
                        progressMessage = "Processing part \(index + 1) of \(chunks.count)..."
                    }

                    // Create a fresh session for each chunk to avoid context buildup
                    let chunkSession = LanguageModelSession()
                    let chunkPrompt = """
                    Extract information from this meeting transcript segment. Use EXACTLY this format with these section headers:

                    [SUMMARY]
                    Brief overview of what was discussed

                    [KEY POINTS]
                    - Point 1
                    - Point 2

                    [DECISIONS]
                    - Decision 1
                    - Decision 2

                    [ACTION ITEMS]
                    - Action 1
                    - Action 2

                    Transcript:
                    \(chunk)
                    """
                    let response = try await chunkSession.respond(to: chunkPrompt)
                    chunkSummaries.append(response.content)
                }

                // Store raw summaries for potential merging later
                await MainActor.run {
                    rawChunkSummaries = chunkSummaries
                }

                // Format notes with parts
                let combinedSummaries = chunkSummaries.enumerated()
                    .map { "## Part \($0.offset + 1)\n\($0.element)" }
                    .joined(separator: "\n\n---\n\n")

                generatedNotes = """
                # Meeting Notes

                \(combinedSummaries)
                """

                // Enable merge option
                await MainActor.run {
                    canMergeNotes = true
                }
            }
        } catch {
            let errorMessage = error.localizedDescription
            if errorMessage.contains("context") || errorMessage.contains("token") || errorMessage.contains("length") {
                generatedNotes = "The transcript is too long for the on-device model.\n\nTry with a shorter recording (under 10 minutes works best)."
            } else {
                generatedNotes = "Failed to generate notes: \(errorMessage)"
            }
        }
        #else
        generatedNotes = "Apple Intelligence is not available on this platform"
        #endif
        await MainActor.run { isGeneratingNotes = false }
    }

    @available(iOS 26, macOS 26, *)
    private func mergeNotes() async {
        #if canImport(FoundationModels)
        guard !rawChunkSummaries.isEmpty else {
            await MainActor.run { isMerging = false }
            return
        }

        await MainActor.run {
            progressMessage = "Extracting sections from all parts..."
        }

        // Extract sections from each part and combine them directly
        var allSummaries: [String] = []
        var allKeyPoints: [String] = []
        var allDecisions: [String] = []
        var allActionItems: [String] = []

        for (index, summary) in rawChunkSummaries.enumerated() {
            let extracted = extractSections(from: summary, partNumber: index + 1)
            if !extracted.summary.isEmpty {
                allSummaries.append(extracted.summary)
            }
            allKeyPoints.append(contentsOf: extracted.keyPoints)
            allDecisions.append(contentsOf: extracted.decisions)
            allActionItems.append(contentsOf: extracted.actionItems)
        }

        // Build the merged notes directly without re-summarizing
        var mergedNotes = "# Meeting Notes\n\n"

        // Summaries section - combine part summaries
        if !allSummaries.isEmpty {
            mergedNotes += "## Summary\n\n"
            for (index, summary) in allSummaries.enumerated() {
                if allSummaries.count > 1 {
                    mergedNotes += "**Part \(index + 1):** \(summary)\n\n"
                } else {
                    mergedNotes += "\(summary)\n\n"
                }
            }
        }

        // Key Points - deduplicated list
        if !allKeyPoints.isEmpty {
            mergedNotes += "## Key Points\n\n"
            let uniquePoints = removeDuplicates(from: allKeyPoints)
            for point in uniquePoints {
                mergedNotes += "- \(point)\n"
            }
            mergedNotes += "\n"
        }

        // Decisions - deduplicated list
        if !allDecisions.isEmpty {
            mergedNotes += "## Decisions\n\n"
            let uniqueDecisions = removeDuplicates(from: allDecisions)
            for decision in uniqueDecisions {
                mergedNotes += "- \(decision)\n"
            }
            mergedNotes += "\n"
        }

        // Action Items - deduplicated list
        if !allActionItems.isEmpty {
            mergedNotes += "## Action Items\n\n"
            let uniqueActions = removeDuplicates(from: allActionItems)
            for action in uniqueActions {
                mergedNotes += "- \(action)\n"
            }
        }

        await MainActor.run {
            generatedNotes = mergedNotes
            canMergeNotes = false
            isMerging = false
        }
        #else
        await MainActor.run { isMerging = false }
        #endif
    }

    private func extractSections(from text: String, partNumber: Int) -> (summary: String, keyPoints: [String], decisions: [String], actionItems: [String]) {
        var summary = ""
        var keyPoints: [String] = []
        var decisions: [String] = []
        var actionItems: [String] = []

        // Split by section headers
        let sections = text.components(separatedBy: "[")

        for section in sections {
            let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("SUMMARY]") {
                let content = trimmed.replacingOccurrences(of: "SUMMARY]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                summary = content.components(separatedBy: "\n").first ?? content
            } else if trimmed.hasPrefix("KEY POINTS]") {
                let content = trimmed.replacingOccurrences(of: "KEY POINTS]", with: "")
                keyPoints = extractBulletPoints(from: content)
            } else if trimmed.hasPrefix("DECISIONS]") {
                let content = trimmed.replacingOccurrences(of: "DECISIONS]", with: "")
                decisions = extractBulletPoints(from: content)
            } else if trimmed.hasPrefix("ACTION ITEMS]") {
                let content = trimmed.replacingOccurrences(of: "ACTION ITEMS]", with: "")
                actionItems = extractBulletPoints(from: content)
            }
        }

        return (summary, keyPoints, decisions, actionItems)
    }

    private func extractBulletPoints(from text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var points: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                let point = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !point.isEmpty && point.lowercased() != "none" && point.lowercased() != "n/a" {
                    points.append(point)
                }
            } else if trimmed.hasPrefix("• ") {
                let point = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !point.isEmpty && point.lowercased() != "none" && point.lowercased() != "n/a" {
                    points.append(point)
                }
            }
        }

        return points
    }

    private func removeDuplicates(from items: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []

        for item in items {
            let normalized = item.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if !seen.contains(normalized) {
                seen.insert(normalized)
                unique.append(item)
            }
        }

        return unique
    }

    private func splitIntoChunks(text: String, maxSize: Int) -> [String] {
        var chunks: [String] = []
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            let endIndex = text.index(currentIndex, offsetBy: maxSize, limitedBy: text.endIndex) ?? text.endIndex

            // Try to break at a sentence or paragraph boundary
            var breakIndex = endIndex
            if endIndex < text.endIndex {
                let searchRange = text.index(endIndex, offsetBy: -200, limitedBy: currentIndex) ?? currentIndex
                let substring = text[searchRange..<endIndex]

                if let lastPeriod = substring.lastIndex(of: ".") {
                    breakIndex = text.index(after: lastPeriod)
                } else if let lastNewline = substring.lastIndex(of: "\n") {
                    breakIndex = text.index(after: lastNewline)
                }
            }

            let chunk = String(text[currentIndex..<breakIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            currentIndex = breakIndex
        }

        return chunks
    }
}

#Preview {
    NavigationStack {
        TranscriptionDetailView(transcription: Transcription(
            title: "Sample Transcription",
            transcriptionText: "This is a sample transcription text that demonstrates how the detail view looks with actual content. It can be quite long and should wrap properly.",
            language: "en-US",
            duration: 125
        ))
    }
    .modelContainer(for: Transcription.self, inMemory: true)
}

