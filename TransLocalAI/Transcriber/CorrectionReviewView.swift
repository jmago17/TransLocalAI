//
//  CorrectionReviewView.swift
//  Transcriber
//

import SwiftUI
import SwiftData

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, macOS 26, *)
struct CorrectionReviewView: View {
    @Bindable var transcription: Transcription
    @Environment(\.dismiss) private var dismiss

    @State private var corrections: [TranscriptionCorrection] = []
    @State private var isAnalyzing = true
    @State private var analysisProgress = ""
    @State private var errorMessage: String?
    @State private var selectedFilter: String? = nil
    @State private var analysisTask: Task<Void, Never>?

    private let filters = [
        ("All", nil as String?),
        ("Mishearing", "mishearing" as String?),
        ("Grammar", "grammar" as String?),
        ("Punctuation", "punctuation" as String?),
        ("Formatting", "formatting" as String?),
        ("Filler", "fillerWord" as String?),
        ("Unclear", "unclear" as String?),
    ]

    private var filteredCorrections: [TranscriptionCorrection] {
        guard let filter = selectedFilter else { return corrections }
        return corrections.filter { $0.category == filter }
    }

    private var acceptedCount: Int {
        corrections.filter { $0.status == .accepted }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if isAnalyzing {
                    analysisView
                } else if let error = errorMessage {
                    errorView(error)
                } else if corrections.isEmpty {
                    noCorrectionView
                } else {
                    correctionListView
                }
            }
            .navigationTitle("AI Review")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        analysisTask?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { startAnalysis() }
    }

    // MARK: - Subviews

    private var analysisView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Analyzing transcription...")
                .font(.headline)
            Text(analysisProgress)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Analysis Failed")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { startAnalysis() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var noCorrectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("No corrections found")
                .font(.headline)
            Text("The transcription looks good!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var correctionListView: some View {
        VStack(spacing: 0) {
            // Summary bar
            Text("\(corrections.count) corrections found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.0) { label, value in
                        let isSelected = selectedFilter == value
                        Button {
                            selectedFilter = value
                        } label: {
                            Text(label)
                                .font(.caption)
                                .fontWeight(isSelected ? .semibold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? Color.accentColor : Color(.tertiarySystemBackground))
                                .foregroundStyle(isSelected ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            // Correction cards
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredCorrections) { correction in
                        correctionCard(correction)
                    }
                }
                .padding()
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Accept All") {
                    for correction in corrections where correction.status == .pending {
                        correction.status = .accepted
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Apply \(acceptedCount) Accepted") {
                    applyCorrections()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(acceptedCount == 0)
            }
            .padding()
        }
    }

    private func correctionCard(_ correction: TranscriptionCorrection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: category badge + confidence
            HStack {
                Label(correction.displayCategory, systemImage: correction.categoryIcon)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(categoryBackground(correction.categoryColor))
                    .clipShape(Capsule())

                Spacer()

                Text("Confidence: \(correction.confidence)/10")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Original → Suggested
            VStack(alignment: .leading, spacing: 4) {
                Text(correction.originalText)
                    .strikethrough()
                    .foregroundStyle(.red)
                    .font(.subheadline)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(correction.suggestedText)
                    .foregroundStyle(.green)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            // Reason
            Text(correction.reason)
                .font(.caption)
                .foregroundStyle(.secondary)

            // User override for unclear items
            if correction.category == "unclear" {
                TextField("Your correction...", text: Binding(
                    get: { correction.userOverride ?? "" },
                    set: { correction.userOverride = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            }

            // Accept / Reject buttons
            HStack {
                Button {
                    correction.status = correction.status == .accepted ? .pending : .accepted
                } label: {
                    Label("Accept", systemImage: correction.status == .accepted ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(correction.status == .accepted ? .green : .gray)

                Button {
                    correction.status = correction.status == .rejected ? .pending : .rejected
                } label: {
                    Label("Reject", systemImage: correction.status == .rejected ? "xmark.circle.fill" : "xmark.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(correction.status == .rejected ? .red : .gray)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .opacity(correction.status == .rejected ? 0.5 : 1.0)
    }

    private func categoryBackground(_ colorName: String) -> Color {
        switch colorName {
        case "red": return Color.red.opacity(0.15)
        case "orange": return Color.orange.opacity(0.15)
        case "blue": return Color.blue.opacity(0.15)
        case "purple": return Color.purple.opacity(0.15)
        case "gray": return Color.gray.opacity(0.15)
        case "yellow": return Color.yellow.opacity(0.15)
        default: return Color.gray.opacity(0.15)
        }
    }

    // MARK: - Logic

    private func startAnalysis() {
        isAnalyzing = true
        errorMessage = nil
        corrections = []

        analysisTask = Task {
            do {
                let results = try await AICorrectionService.analyzeTranscription(
                    text: transcription.transcriptionText,
                    language: transcription.language
                ) { completed, total in
                    Task { @MainActor in
                        analysisProgress = "Processing chunk \(completed + 1) of \(total)..."
                    }
                }
                corrections = results
            } catch is CancellationError {
                // User dismissed — nothing to do
            } catch {
                errorMessage = error.localizedDescription
            }
            isAnalyzing = false
        }
    }

    /// Apply accepted corrections in reverse order so indices stay valid.
    private func applyCorrections() {
        let accepted = corrections
            .filter { $0.status == .accepted && $0.rangeInText != nil }
            .sorted { lhs, rhs in
                // Sort by position in text, reverse order (end-to-start)
                guard let l = lhs.rangeInText, let r = rhs.rangeInText else { return false }
                return l.lowerBound > r.lowerBound
            }

        var text = transcription.transcriptionText
        for correction in accepted {
            // Re-find the range in case prior edits shifted things (shouldn't happen with reverse order, but safe)
            if let range = text.range(of: correction.originalText) {
                text.replaceSubrange(range, with: correction.effectiveReplacement)
            } else if let range = text.range(of: correction.originalText, options: .caseInsensitive) {
                text.replaceSubrange(range, with: correction.effectiveReplacement)
            }
        }
        transcription.transcriptionText = text
    }
}
#endif
