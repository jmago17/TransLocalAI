//
//  AICorrectionService.swift
//  Transcriber
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, macOS 26, *)
struct AICorrectionService {
    /// Suggestions only; the caller must explicitly accept them before applying.
    static func analyzeTranscription(
        text: String,
        language: String,
        progressCallback: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [TranscriptionCorrection] {
        let chunks = splitIntoChunks(text: text, maxSize: 6000)
        var allCorrections: [TranscriptionCorrection] = []
        let vocabulary = await MainActor.run { TranscriptionVocabulary.canonicalTerms }

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            progressCallback?(index, chunks.count)
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: buildPrompt(for: chunk.text, language: language, vocabulary: vocabulary),
                generating: CorrectionBatch.self
            )
            allCorrections += validate(
                response.content.corrections,
                in: chunk,
                fullText: text,
                excluding: allCorrections
            )
        }
        progressCallback?(chunks.count, chunks.count)
        return allCorrections
    }

    // Character offsets are measured in Swift String characters, not UTF-8 or UTF-16.
    // Every chunk is contiguous in the original transcript, including its newlines.
    struct Chunk {
        let text: String
        let startOffset: Int
    }

    static func splitIntoChunks(text: String, maxSize: Int) -> [Chunk] {
        guard !text.isEmpty, maxSize > 0 else { return [] }
        var result: [Chunk] = []
        var start = text.startIndex
        var offset = 0
        while start < text.endIndex {
            let limit = text.index(start, offsetBy: maxSize, limitedBy: text.endIndex) ?? text.endIndex
            var end = limit
            if limit < text.endIndex, let newline = text[start..<limit].lastIndex(of: "\n") {
                // Keep the newline in this chunk; never generate an empty chunk.
                end = text.index(after: newline)
            }
            let part = String(text[start..<end])
            result.append(Chunk(text: part, startOffset: offset))
            offset += part.count
            start = end
        }
        return result
    }

    /// Pure validation: a model response cannot choose another occurrence in the transcript.
    /// Competing suggestions that touch the same original text are both discarded.
    static func validate(
        _ proposals: [SingleCorrection],
        in chunk: Chunk,
        fullText: String,
        excluding previous: [TranscriptionCorrection] = []
    ) -> [TranscriptionCorrection] {
        guard chunk.startOffset >= 0,
              let chunkStart = fullText.index(fullText.startIndex, offsetBy: chunk.startOffset, limitedBy: fullText.endIndex),
              fullText[chunkStart...].hasPrefix(chunk.text) else { return [] }

        let timestampRanges = timestampRanges(in: fullText)
        var candidates: [TranscriptionCorrection] = []
        for proposal in proposals.prefix(20) {
            let original = proposal.originalText
            let suggested = proposal.suggestedText
            guard proposal.category == .mishearing || proposal.category == .unclear,
                  !original.isEmpty,
                  proposal.startOffset >= 0,
                  let localStart = chunk.text.index(chunk.text.startIndex, offsetBy: proposal.startOffset, limitedBy: chunk.text.endIndex),
                  let localEnd = chunk.text.index(localStart, offsetBy: original.count, limitedBy: chunk.text.endIndex),
                  chunk.text[localStart..<localEnd] == original,
                  let absoluteStart = fullText.index(chunkStart, offsetBy: proposal.startOffset, limitedBy: fullText.endIndex),
                  let absoluteEnd = fullText.index(absoluteStart, offsetBy: original.count, limitedBy: fullText.endIndex),
                  absoluteStart < absoluteEnd,
                  fullText[absoluteStart..<absoluteEnd] == original,
                  !timestampRanges.contains(where: { $0.overlaps(absoluteStart..<absoluteEnd) }),
                  isSafeWord(original), isSafeWord(suggested),
                  (proposal.category == .unclear || original != suggested) else { continue }

            // A word must be complete: no partial matches inside another word.
            if absoluteStart > fullText.startIndex,
               isWordCharacter(fullText[fullText.index(before: absoluteStart)]) { continue }
            if absoluteEnd < fullText.endIndex,
               isWordCharacter(fullText[absoluteEnd]) { continue }

            let correction = TranscriptionCorrection(
                originalText: original,
                suggestedText: suggested,
                category: proposal.category.rawValue,
                reason: proposal.reason,
                confidence: min(max(proposal.confidence, 1), 10)
            )
            correction.rangeInText = absoluteStart..<absoluteEnd
            correction.characterOffset = chunk.startOffset + proposal.startOffset
            candidates.append(correction)
        }
        return candidates.filter { candidate in
            guard let range = candidate.rangeInText else { return false }
            return !previous.contains(where: { $0.rangeInText?.overlaps(range) == true })
                && candidates.filter { $0.rangeInText?.overlaps(range) == true }.count == 1
        }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }
    }

    private static func isSafeWord(_ word: String) -> Bool {
        !word.isEmpty && word.unicodeScalars.allSatisfy {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }

    private static func timestampRanges(in text: String) -> [Range<String.Index>] {
        // Bare SRT/VTT timecodes and bracketed inline markers (also with hours/milliseconds).
        let pattern = #"\[?\d{1,2}:\d{2}(?::\d{2})?(?:[.,]\d{1,3})?\]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: nsRange).compactMap { Range($0.range, in: text) }
    }

    private static func buildPrompt(for chunk: String, language: String, vocabulary: [String]) -> String {
        let vocabularyRule = vocabulary.isEmpty ? "" :
            "\nThese names and terms are already correct; do not flag them: \(vocabulary.joined(separator: ", "))."
        return """
        You are checking ASR recognition errors ONLY, in language \(language).\(vocabularyRule)
        Suggest ONLY a clearly misheard single word or a single unclear word needing human review.
        Do not correct grammar, style, punctuation, capitalization, formatting, filler words or meaning.
        Never add, delete or reorder words. Never invent what a speaker may have said.
        If unsure, return no suggestion. Do not change timestamps or their surrounding markers.
        For each suggestion, copy originalText EXACTLY from the input, and give startOffset as
        the zero-based Swift-character position of that precise occurrence WITHIN this chunk.
        If a word occurs more than once, identify its specific occurrence by position.
        suggestedText must be one word, not a phrase. For unclear words, use the original
        as suggestedText if no safe replacement is known; the user can enter a correction.
        At most 20 suggestions. All suggestions require the user's explicit approval.

        Transcript chunk:
        \(chunk)
        """
    }
}
#endif
