//
//  AICorrectionService.swift
//  Transcriber
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, macOS 26, *)
struct AICorrectionService {
    /// Analyze a transcription and return suggested corrections.
    /// - Parameters:
    ///   - text: The full transcription text
    ///   - language: The language code (e.g. "en-US")
    ///   - progressCallback: Called with (completedChunks, totalChunks)
    /// - Returns: Array of corrections with text ranges resolved
    static func analyzeTranscription(
        text: String,
        language: String,
        progressCallback: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [TranscriptionCorrection] {
        let chunks = splitIntoChunks(text: text, maxSize: 6000)
        var allCorrections: [TranscriptionCorrection] = []

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            progressCallback?(index, chunks.count)

            let session = LanguageModelSession()
            let prompt = buildPrompt(for: chunk, language: language)
            let response = try await session.respond(to: prompt, generating: CorrectionBatch.self)

            let corrections = response.content.corrections.prefix(20).map { single in
                let correction = TranscriptionCorrection(
                    originalText: single.originalText,
                    suggestedText: single.suggestedText,
                    category: single.category.rawValue,
                    reason: single.reason,
                    confidence: min(max(single.confidence, 1), 10)
                )
                // Resolve range in the full text
                correction.rangeInText = findRange(of: single.originalText, in: text)
                return correction
            }

            // Only include corrections where we found a match in the text
            allCorrections.append(contentsOf: corrections.filter { $0.rangeInText != nil })
        }

        progressCallback?(chunks.count, chunks.count)
        return allCorrections
    }

    // MARK: - Private

    private static func buildPrompt(for chunk: String, language: String) -> String {
        """
        You are a transcription proofreader. Analyze the following transcribed text and find errors.

        Look for these categories of issues:
        - mishearing: Words that were likely misheard by the speech recognizer (e.g., "their" instead of "there")
        - grammar: Grammatical errors
        - punctuation: Missing or incorrect punctuation
        - formatting: Formatting issues (e.g., inconsistent capitalization)
        - fillerWord: Filler words that could be removed (e.g., "um", "uh", "like", "you know")
        - unclear: Parts that seem garbled or nonsensical and need human review

        Rules:
        - NEVER modify timestamp markers like [00:00] or [1:23:45]. Leave them exactly as they are.
        - The originalText must be an EXACT substring of the input text (copy it character-for-character).
        - Keep corrections concise and focused.
        - For filler words, the suggestedText should be the text with the filler removed.
        - Maximum 20 corrections per batch.
        - The text language is: \(language)

        Text to analyze:
        \(chunk)
        """
    }

    /// Split text into chunks at line boundaries, preserving timestamp lines intact.
    private static func splitIntoChunks(text: String, maxSize: Int) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var chunks: [String] = []
        var currentChunk = ""

        for line in lines {
            let candidate = currentChunk.isEmpty ? line : currentChunk + "\n" + line
            if candidate.count > maxSize && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = line
            } else {
                currentChunk = candidate
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks.isEmpty ? [text] : chunks
    }

    /// Find the range of `needle` in `haystack`, with case-insensitive fallback.
    private static func findRange(of needle: String, in haystack: String) -> Range<String.Index>? {
        // Exact match first
        if let range = haystack.range(of: needle) {
            return range
        }
        // Case-insensitive fallback
        if let range = haystack.range(of: needle, options: .caseInsensitive) {
            return range
        }
        // Trimmed match — AI sometimes adds/removes whitespace
        let trimmed = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != needle, let range = haystack.range(of: trimmed) {
            return range
        }
        return nil
    }
}
#endif
