import Foundation
import ModelStore
import Voz

/// Policy is deliberately independent of SDK initialization and language detection.
nonisolated enum VozLanguagePolicy {
    static let supported: Set<String> = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu", "it",
        "lt", "lv", "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk"
    ]
    static func base(_ language: String) -> String {
        language.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-").lowercased()
            .split(separator: "-", omittingEmptySubsequences: false).first.map(String.init) ?? ""
    }
    static func supports(_ language: String) -> Bool { supported.contains(base(language)) }
    static func validate(_ language: String) throws {
        guard supports(language) else { throw TranscriptionEngineError.unsupportedLanguage(language) }
    }
}

/// No network or license check until an explicitly selected request prepares the model.
actor VozTranscriptionEngine: ModelPreparingTranscriptionEngine {
    static let shared = VozTranscriptionEngine()
    private var model: Voz?
    private var loading = false

    nonisolated static var isDownloaded: Bool { Voz.isDownloaded() }

    func detectLanguage(audioURL: URL) async throws -> String {
        throw TranscriptionEngineError.unsupportedLanguage("Voz requires an explicit supported language")
    }

    func prepareModel(for language: String, progress: (@Sendable (Double) -> Void)?) async throws {
        try VozLanguagePolicy.validate(language)
        try Task.checkCancellation()
        // Keep initialization in the caller's task so cancellation is not lost in a detached task.
        // Other callers wait cooperatively instead of loading a second 337 MB model.
        while loading {
            try await Task.sleep(for: .milliseconds(100))
        }
        if model != nil { progress?(1); return }
        loading = true
        defer { loading = false }
        progress?(0)
        let directory = try await Voz.download { update in
            guard !Task.isCancelled else { return }
            progress?(update.fraction)
        }
        try Task.checkCancellation()
        let loaded = try await Voz(directory: directory)
        try Task.checkCancellation()
        model = loaded
        progress?(1)
    }

    func transcribe(audioURL: URL, language: String, progress: (@Sendable (Double) -> Void)?) async throws -> TranscriptionResult {
        try VozLanguagePolicy.validate(language)
        try await prepareModel(for: language, progress: nil)
        try Task.checkCancellation()
        guard let model else { throw TranscriptionEngineError.modelUnavailable }
        let terms = await MainActor.run { Array(TranscriptionTerminology.whisperPromptTerms().prefix(16)) }
        let result = try await model.transcribe(audioURL, vocabulary: terms) { update in
            guard !Task.isCancelled else { return }
            progress?(update.fractionCompleted)
        }
        // SDK inference is not immediately cancellable; never publish a cancelled result.
        try Task.checkCancellation()
        let vocabulary = await MainActor.run { TranscriptionVocabulary.terms }
        let formatted = VozTranscriptFormatter.format(
            words: result.words.map { .init(text: $0.text, start: $0.start, end: $0.end) },
            fallback: result.text
        )
        let corrected = TranscriptionVocabulary.correcting(formatted, terms: vocabulary)
        return TranscriptionResult(text: corrected, language: language,
                                   duration: result.duration, engineUsed: .voz)
    }
}

nonisolated enum VozTranscriptFormatter {
    struct Word: Sendable {
        let text: String
        let start: Double
        let end: Double
    }
    static func format(words: [Word], fallback: String) -> String {
        var lines: [String] = []
        var text = ""
        var start = 0.0
        var end = 0.0
        func flush() {
            guard !text.isEmpty else { return }
            let seconds = Int(max(0, start.isFinite ? start : 0))
            let stamp = seconds >= 3600
                ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
                : String(format: "%02d:%02d", seconds / 60, seconds % 60)
            lines.append("[\(stamp)] \(text)")
            text = ""
        }
        for word in words {
            let piece = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            if !text.isEmpty && (word.start - end >= 1.5 || word.start - start >= 20 || text.count >= 240) { flush() }
            if text.isEmpty { start = word.start }
            let closes = piece.first.map { ",.;:!?%)]}»”".contains($0) } ?? false
            let opens = text.last.map { "([{«¿¡“".contains($0) } ?? false
            if !text.isEmpty && !closes && !opens { text += " " }
            text += piece
            end = word.end
            if piece.last.map({ ".!?".contains($0) }) == true { flush() }
        }
        flush()
        if lines.isEmpty {
            let trimmed = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "" : "[00:00] \(trimmed)"
        }
        return lines.joined(separator: "\n")
    }
}
