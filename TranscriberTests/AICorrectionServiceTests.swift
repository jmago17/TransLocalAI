import Foundation
import Testing
@testable import Transcriber

#if canImport(FoundationModels)
struct AICorrectionServiceTests {
    private func proposal(_ original: String, _ suggested: String, at offset: Int,
                          category: CorrectionCategory = .mishearing) -> SingleCorrection {
        SingleCorrection(startOffset: offset, originalText: original,
                         suggestedText: suggested, category: category,
                         reason: "Possible recognition error", confidence: 8)
    }

    @Test func repeatedSubstringInLaterChunkUsesExactOccurrence() {
        let text = "foo\nfoo\nfoo"
        let chunks = AICorrectionService.splitIntoChunks(text: text, maxSize: 4)
        #expect(chunks.map(\.text) == ["foo\n", "foo\n", "foo"])
        #expect(chunks.map(\.startOffset) == [0, 4, 8])
        let corrections = AICorrectionService.validate(
            [proposal("foo", "bar", at: 0)], in: chunks[2], fullText: text
        )
        #expect(corrections.count == 1)
        #expect(corrections.first?.characterOffset == 8)
        #expect(corrections.first?.rangeInText.map { String(text[$0]) } == "foo")
    }

    @Test func repeatedWordsWithinChunkNeedCorrectOffset() {
        let text = "alpha alpha"
        let chunk = AICorrectionService.splitIntoChunks(text: text, maxSize: 40)[0]
        let result = AICorrectionService.validate([proposal("alpha", "beta", at: 6)],
                                                   in: chunk, fullText: text)
        #expect(result.first?.characterOffset == 6)
        #expect(AICorrectionService.validate([proposal("alpha", "beta", at: 5)],
                                               in: chunk, fullText: text).isEmpty)
    }

    @Test func rejectsMalformedAndEditorialProposals() {
        let text = "busquera hoy bien"
        let chunk = AICorrectionService.splitIntoChunks(text: text, maxSize: 100)[0]
        let proposals = [
            proposal("", "busqueda", at: 0),
            proposal("BUSQUERA", "busqueda", at: 0),
            proposal("busquera", "la busqueda", at: 0),
            proposal("busquera", "", at: 0),
            proposal("hoy", "ayer", at: -1),
            proposal("hoy", "ayer", at: 100),
            proposal("hoy", "ayer", at: 9, category: .grammar),
            proposal("bien", "mejor", at: 13, category: .punctuation),
            proposal("bus", "busqueda", at: 0)
        ]
        #expect(AICorrectionService.validate(proposals, in: chunk, fullText: text).isEmpty)
        let valid = AICorrectionService.validate([proposal("busquera", "busqueda", at: 0)],
                                                  in: chunk, fullText: text)
        #expect(valid.count == 1) // no hard-coded vocabulary required
    }

    @Test func rejectsBothOverlappingSuggestions() {
        let text = "busquera ahora"
        let chunk = AICorrectionService.splitIntoChunks(text: text, maxSize: 100)[0]
        let proposals = [proposal("busquera", "busqueda", at: 0),
                         proposal("busquera", "busquero", at: 0)]
        #expect(AICorrectionService.validate(proposals, in: chunk, fullText: text).isEmpty)
        let prior = AICorrectionService.validate([proposals[0]], in: chunk, fullText: text)
        #expect(AICorrectionService.validate([proposals[1]], in: chunk,
                                               fullText: text, excluding: prior).isEmpty)
    }

    @Test func rejectsTimestampsEvenWhenWordLikeNumbers() {
        let text = "[00:12] foo\n00:00:01,000 --> 00:00:04,000\nfoo"
        let chunk = AICorrectionService.splitIntoChunks(text: text, maxSize: 100)[0]
        let proposals = [proposal("00", "01", at: 1),
                         proposal("12", "13", at: 4),
                         proposal("01", "02", at: 18),
                         proposal("foo", "bar", at: 8)]
        let result = AICorrectionService.validate(proposals, in: chunk, fullText: text)
        #expect(result.count == 1)
        #expect(result.first?.originalText == "foo")
    }

    @Test func longLineNeverExceedsChunkLimitAndPreservesText() {
        let text = String(repeating: "á", count: 31) + "\n" + String(repeating: "b", count: 23)
        let chunks = AICorrectionService.splitIntoChunks(text: text, maxSize: 10)
        #expect(chunks.allSatisfy { $0.text.count <= 10 && !$0.text.isEmpty })
        #expect(chunks.map(\.text).joined() == text)
        #expect(chunks.last?.startOffset == 52)
    }
}
#endif
