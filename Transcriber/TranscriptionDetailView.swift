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

struct TranscriptionDetailView: View {
    @Bindable var transcription: Transcription
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var isTranscribing = false
    @State private var transcriptionError: String?
    @State private var retranscribeLanguage = "multilingual"

    @State private var isGeneratingNotes = false
    @State private var generatedNotes: String?
    @State private var showNotes = false
    @State private var showPromptCustomization = false
    @State private var progressMessage = "Generating notes..."
    @State private var showCorrectionReview = false
    @State private var vocabularyFixCount: Int?
    @State private var showSuspiciousTerms = false
    @State private var replaceCandidate = ""
    @State private var replacementText = ""
    @State private var showReplaceDialog = false

    private let defaultPrompt = MeetingNotesService.shortcutPrompt

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
                            Label(isGeneratingNotes ? "Generating Notes…" : "Generate Meeting Notes", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(transcription.transcriptionText.isEmpty || isGeneratingNotes)

                        if !transcription.meetingNotes.isEmpty {
                            Button {
                                generatedNotes = transcription.meetingNotes
                                showNotes = true
                            } label: {
                                Label("View Saved Meeting Notes", systemImage: "doc.text.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            showCorrectionReview = true
                        } label: {
                            Label("AI Review", systemImage: "text.badge.checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(transcription.transcriptionText.isEmpty)

                        HStack(spacing: 12) {
                            Button(action: applyVocabulary) {
                                Label(
                                    vocabularyFixCount.map { $0 == 0 ? "No Changes" : "\($0) Fixed" }
                                        ?? "Fix Names",
                                    systemImage: vocabularyFixCount == nil ? "character.magnify" : "checkmark"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(transcription.transcriptionText.isEmpty || vocabularyFixCount != nil)

                            Button {
                                showSuspiciousTerms = true
                            } label: {
                                Label("Suspicious", systemImage: "questionmark.text.page")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(transcription.transcriptionText.isEmpty)
                        }

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
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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

                // Transcribe / Retranscribe actions when audio file exists
                if transcription.audioFileURL != nil {
                    if isTranscribing {
                        VStack(spacing: 12) {
                            TranscribingAnimation(size: CGSize(width: 150, height: 66))
                            Text("Transcribing...")
                                .font(.headline)
                            Text("This may take a few moments")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    } else {
                        VStack(spacing: 12) {
                            // Language picker
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Language")
                                    .font(.headline)

                                Picker("Language", selection: $retranscribeLanguage) {
                                    Text("Multilingual").tag("multilingual")
                                    Text("Euskara").tag("eu-ES")
                                    Text("Español").tag("es-ES")
                                    Text("English").tag("en-US")
                                }
                                .pickerStyle(.segmented)
                            }

                            Button(action: transcribeAudio) {
                                Label(
                                    transcription.transcriptionText.isEmpty ? "Transcribe Now" : "Retranscribe",
                                    systemImage: transcription.transcriptionText.isEmpty ? "text.bubble" : "arrow.counterclockwise"
                                )
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            if let audioURL = resolvedAudioURL {
                                ShareLink(item: audioURL, preview: SharePreview(transcription.title, image: Image(systemName: "waveform"))) {
                                    Label("Share Audio", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            }

                            if let error = transcriptionError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }

                // Transcription text
                if isEditing {
                    TextEditor(text: $transcription.transcriptionText)
                        .frame(minHeight: 300)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                } else if !transcription.transcriptionText.isEmpty {
                    #if os(iOS)
                    SelectableTranscriptView(text: transcription.transcriptionText) { selected in
                        replaceCandidate = selected
                        replacementText = ""
                        showReplaceDialog = true
                    }
                    #else
                    Text(transcription.transcriptionText)
                        .textSelection(.enabled)
                        .font(.body)
                    #endif
                }

                Spacer()
            }
            .padding()
        }
        .liquidCrystalScreen()
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
                    if let audioURL = resolvedAudioURL {
                        ShareLink(item: audioURL, preview: SharePreview(transcription.title, image: Image(systemName: "waveform"))) {
                            Image(systemName: "waveform.circle")
                        }
                    }
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

                            Divider()

                            Text(notes)
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                }
                .liquidCrystalScreen()
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
        .sheet(isPresented: $showCorrectionReview) {
            if #available(iOS 26, macOS 26, *) {
                CorrectionReviewView(transcription: transcription)
            }
        }
        .sheet(isPresented: $showSuspiciousTerms) {
            SuspiciousTermsView(transcription: transcription)
        }
        .alert("Replace “\(replaceCandidate)”", isPresented: $showReplaceDialog) {
            TextField("Correct spelling", text: $replacementText)
                .autocorrectionDisabled()
            Button("Replace & Save") { applyManualReplacement() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Replaces every occurrence and adds it to your names list, so future transcriptions get it right.")
        }
    }

    private var resolvedAudioURL: URL? {
        guard let audioFileName = transcription.audioFileURL else { return nil }
        return AudioFileManager.shared.audioURL(for: audioFileName)
    }

    private func transcribeAudio() {
        guard let audioURL = resolvedAudioURL else { return }
        isTranscribing = true
        transcriptionError = nil

        Task { @MainActor in
            let hybridService = HybridTranscriptionService()
            do {
                try await hybridService.prepareModelIfNeeded(language: retranscribeLanguage) { _ in }

                let result = try await hybridService.transcribe(
                    audioURL: audioURL,
                    language: retranscribeLanguage
                )

                transcription.transcriptionText = result.text
                transcription.language = result.language
                transcription.duration = result.duration
                transcription.engineUsed = result.engineUsed == .appleSpeech ? "apple" : "whisper"
                isTranscribing = false
            } catch {
                isTranscribing = false
                transcriptionError = "Transcription failed: \(error.localizedDescription)"
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
        do {
            progressMessage = MeetingNotesService.willUsePrivateCloudCompute
                ? "Analyzing transcript with Private Cloud Compute..."
                : "Analyzing transcript on this device..."
            let notes = try await MeetingNotesService.generate(
                from: transcription.transcriptionText,
                title: transcription.title,
                instructions: customPrompt
            )
            generatedNotes = notes
            transcription.meetingNotes = notes
            try modelContext.save()
        } catch {
            generatedNotes = "Failed to generate notes: \(error.localizedDescription)"
        }
        isGeneratingNotes = false
    }

    /// Applies a selection-driven fix everywhere in the transcript and stores
    /// it as a vocabulary alias for future transcriptions.
    private func applyManualReplacement() {
        let variant = replaceCandidate
        let canonical = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty, !variant.isEmpty, canonical != variant else { return }

        TranscriptionVocabulary.addAlias(canonical: canonical, variant: variant)
        transcription.transcriptionText = TranscriptionVocabulary.correcting(
            transcription.transcriptionText,
            terms: ["\(canonical) = \(variant)"]
        )
        try? modelContext.save()
    }

    /// Re-applies the user's vocabulary (Settings → Names and companies) to an
    /// existing transcript, so terms added after transcribing can fix it too.
    private func applyVocabulary() {
        let original = transcription.transcriptionText
        let corrected = TranscriptionVocabulary.correcting(original)
        if corrected != original {
            transcription.transcriptionText = corrected
            try? modelContext.save()
        }
        vocabularyFixCount = zip(
            original.components(separatedBy: .newlines),
            corrected.components(separatedBy: .newlines)
        ).count(where: { $0 != $1 })
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            vocabularyFixCount = nil
        }
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
