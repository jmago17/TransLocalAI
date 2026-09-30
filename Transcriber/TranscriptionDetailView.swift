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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isEditing = false
    @State private var isTranscribing = false
    @State private var transcriptionError: String?
    @State private var retranscribeLanguage = "multilingual"
    @State private var retranscribeEngine: EnginePreference = .auto
    @State private var retranscribeModelIdentifier = WhisperModelCatalog.defaultModelIdentifier

    @State private var isGeneratingNotes = false
    @State private var generatedNotes: String?
    @State private var showNotes = false
    @State private var showPromptCustomization = false
    @State private var showRetranscriptionOptions = false
    @State private var progressMessage = "Generating notes..."
    @State private var showCorrectionReview = false
    @State private var vocabularyFixCount: Int?
    @State private var showSuspiciousTerms = false
    @State private var replaceCandidate = ""
    @State private var replacementText = ""
    @State private var showReplaceDialog = false
    @State private var showPlayer = false
    @State private var locateWord: String?

    private let defaultPrompt = MeetingNotesService.shortcutPrompt

    @State private var customPrompt: String = ""

    // Imported recordings sometimes append an epoch to the visible title. Keep the
    // original title intact for editing, sharing, persistence and downstream services.
    private var displayTitle: String {
        let title = transcription.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = title.split(separator: " ")
        if title.hasPrefix("Recording "), let last = parts.last,
           (10...13).contains(last.count), last.allSatisfy(\.isNumber) {
            return String(title.dropLast(last.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title.isEmpty ? String(localized: "Untitled Transcription") : title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    if isEditing {
                        TextField("Title", text: $transcription.title)
                            .font(.title2.weight(.semibold))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Text(displayTitle)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                    }

                    ViewThatFits(in: .horizontal) {
                        metadataRow
                        VStack(alignment: .leading, spacing: 6) {
                            metadataRowWithoutDate
                            Text(transcription.timestamp, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                if #available(iOS 26, macOS 26, *) {
                    notesActions
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Transcript")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 12)
                        if resolvedAudioURL != nil && !transcription.transcriptionText.isEmpty {
                            Button {
                                locateWord = nil
                                showPlayer = true
                            } label: {
                                Label("Play with Transcript", systemImage: "play.circle.fill")
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .accessibilityHint("Opens the audio player with synchronized transcript")
                        }
                    }

                    if isEditing {
                        TextEditor(text: $transcription.transcriptionText)
                            .frame(minHeight: 300)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .accessibilityLabel("Transcript text")
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
                    } else {
                        Text("No transcript yet")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if transcription.audioFileURL != nil {
                    retranscriptionSection
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .liquidCrystalScreen()
        .onAppear {
            if customPrompt.isEmpty { customPrompt = defaultPrompt }
        }
        .navigationTitle("Transcription")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if #available(iOS 26, macOS 26, *) {
                        Button {
                            showCorrectionReview = true
                        } label: {
                            Label("AI Review", systemImage: "text.badge.checkmark")
                        }
                        .disabled(transcription.transcriptionText.isEmpty)

                        Button(action: applyVocabulary) {
                            Label(vocabularyFixCount.map { $0 == 0 ? String(localized: "No Changes") :
                                String(localized: "\($0) Fixed") } ?? String(localized: "Fix Names"),
                                  systemImage: "character.magnify")
                        }
                        .disabled(transcription.transcriptionText.isEmpty || vocabularyFixCount != nil)

                        Button {
                            showSuspiciousTerms = true
                        } label: {
                            Label("Suspicious Terms", systemImage: "questionmark.text.page")
                        }
                        .disabled(transcription.transcriptionText.isEmpty)

                        Button {
                            showPromptCustomization = true
                        } label: {
                            Label("Customize Prompt", systemImage: "text.badge.plus")
                        }
                        Divider()
                    }
                    if let audioURL = resolvedAudioURL {
                        ShareLink(item: audioURL, preview: SharePreview(transcription.title, image: Image(systemName: "waveform"))) {
                            Label("Share Audio", systemImage: "waveform")
                        }
                    }
                    if !transcription.transcriptionText.isEmpty {
                        ShareLink(item: transcription.transcriptionText) {
                            Label("Share Transcript", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Label("More Actions", systemImage: "ellipsis.circle")
                }
                .accessibilityLabel("More transcription actions")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
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
        .sheet(isPresented: $showSuspiciousTerms, onDismiss: {
            // "Show in transcript" dismissed the sheet with a word queued up.
            if locateWord != nil {
                showPlayer = true
            }
        }) {
            SuspiciousTermsView(transcription: transcription) { word in
                locateWord = word
            }
        }
        .sheet(isPresented: $showPlayer, onDismiss: { locateWord = nil }) {
            TranscriptPlayerView(
                title: transcription.title,
                transcriptText: transcription.transcriptionText,
                audioURL: resolvedAudioURL,
                locateText: locateWord
            )
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

    private var metadataRow: some View {
        HStack(spacing: 14) {
            metadataRowWithoutDate
            Text(transcription.timestamp, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var metadataRowWithoutDate: some View {
        HStack(spacing: 14) {
            Label(transcription.language == "multilingual" ? String(localized: "Multilingual") : transcription.language,
                  systemImage: "globe")
            if transcription.languageWasAutoDetected {
                Label("Auto-detected", systemImage: "wand.and.stars")
            }
            Label(formatDuration(transcription.duration), systemImage: "clock")
        }
    }

    @available(iOS 26, macOS 26, *)
    private var notesActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 12) { notesButton; savedNotesButton }
            } else {
                HStack(spacing: 12) { notesButton; savedNotesButton }
            }
            if showPromptCustomization {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Customize Prompt").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Done") { showPromptCustomization = false }
                    }
                    TextEditor(text: $customPrompt)
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        .accessibilityLabel("Custom meeting notes prompt")
                    Button("Restore Default") { customPrompt = defaultPrompt }
                        .font(.subheadline)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    @available(iOS 26, macOS 26, *)
    private var notesButton: some View {
        Button {
            isGeneratingNotes = true
            generatedNotes = nil
            progressMessage = "Generating notes..."
            showNotes = true
            Task { await generateMeetingNotes() }
        } label: {
            Label(isGeneratingNotes ? "Generating Notes…" : "Generate Meeting Notes", systemImage: "sparkles")
                .frame(maxWidth: 300)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .controlSize(.large)
        .disabled(transcription.transcriptionText.isEmpty || isGeneratingNotes)
    }

    @available(iOS 26, macOS 26, *)
    @ViewBuilder private var savedNotesButton: some View {
        if !transcription.meetingNotes.isEmpty {
            Button {
                generatedNotes = transcription.meetingNotes
                showNotes = true
            } label: {
                Label("Saved Notes", systemImage: "doc.text")
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var retranscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isTranscribing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Transcribing...").font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            }
            if let error = transcriptionError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        if transcription.transcriptionText.isEmpty {
            Button(action: transcribeAudio) {
                Label("Transcribe Now", systemImage: "text.bubble")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isTranscribing)
        }
        DisclosureGroup(transcription.transcriptionText.isEmpty ? "Transcription options" : "Retranscription options",
                            isExpanded: $showRetranscriptionOptions) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Language", selection: $retranscribeLanguage) {
                        Text("Multilingual").tag("multilingual")
                        Text("Euskara").tag("eu-ES")
                        Text("Español").tag("es-ES")
                        Text("English").tag("en-US")
                    }
                    .pickerStyle(.segmented)

                    TranscriptionModelPicker(
                        engine: $retranscribeEngine,
                        modelIdentifier: $retranscribeModelIdentifier,
                        language: retranscribeLanguage
                    )

                    Button(action: transcribeAudio) {
                        Label(transcription.transcriptionText.isEmpty ? "Transcribe Now" : "Retranscribe",
                              systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTranscribing)
                }
                .padding(.top, 12)
            }
            .tint(.orange)
            .accessibilityHint("Shows language, model and transcription controls")
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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
                try await hybridService.prepareModelIfNeeded(language: retranscribeLanguage, engine: retranscribeEngine, modelIdentifier: retranscribeModelIdentifier) { _ in }

                let result = try await hybridService.transcribe(
                    audioURL: audioURL,
                    language: retranscribeLanguage,
                    engine: retranscribeEngine,
                    modelIdentifier: retranscribeModelIdentifier
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
                instructions: customPrompt,
                onProgress: { progress in
                    Task { @MainActor in
                        switch progress {
                        case .extracting(let part, let total):
                            progressMessage = "Analyzing part \(part) of \(total) on this device..."
                        case .consolidating:
                            progressMessage = "Organizing notes from all parts..."
                        }
                    }
                }
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

        TranscriptionTerminology.recordCorrection(canonical: canonical, variant: variant)
        transcription.transcriptionText = TranscriptionVocabulary.correcting(
            transcription.transcriptionText,
            terms: ["\(canonical): \(variant)"]
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
