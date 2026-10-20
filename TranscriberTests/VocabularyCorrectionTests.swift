import Testing
@testable import Transcriber

struct VocabularyCorrectionTests {
    @Test func preservesUnicodeAndPunctuationAcrossLengthChangingReplacements() {
        let input = "👩🏽‍💻 [00:19] inaki, INAKI; danobat.\n日本語: inaki — café!"
        #expect(TranscriptionVocabulary.correcting(input, terms: ["Iñaki", "Danobat"])
            == "👩🏽‍💻 [00:19] Iñaki, Iñaki; Danobat.\n日本語: Iñaki — café!")
    }

    @Test func preservesDecomposedMarksDuringCorrection() {
        let input = "danobat\u{301} danobat inaki\u{301}"
        #expect(TranscriptionVocabulary.correcting(input, terms: ["Danobat", "Iñaki"])
            == "Danobat\u{301} Danobat Iñaki\u{301}")
    }

    @Test func repeatedMissesAndMatchesPreserveTheirOriginalPositions() {
        let input = String(repeating: "untouched gorosbel, untouched DANOBAT!\n", count: 100)
        let expected = String(repeating: "untouched Gorosabel, untouched Danobat!\n", count: 100)
        #expect(TranscriptionVocabulary.correcting(input, terms: ["Gorosabel", "Danobat"]) == expected)
    }

    @Test func cacheDoesNotSurviveVocabularyChanges() {
        let input = "danobat danobat"
        #expect(TranscriptionVocabulary.correcting(input, terms: ["Danobat"]) == "Danobat Danobat")
        #expect(TranscriptionVocabulary.correcting(input, terms: []) == input)
        #expect(TranscriptionVocabulary.correcting(input, terms: ["DANOBAT"]) == "DANOBAT DANOBAT")
    }

    @Test func preservesOrderedAliasAndPhrasePasses() {
        #expect(TranscriptionVocabulary.correcting(
            "Yankee met ion azpeitia. Yankee!", terms: ["Ianki: Yankee", "Iñaki = Ianki", "Ion Azpeitia"]
        ) == "Iñaki met Ion Azpeitia. Iñaki!")
    }

    @Test func unchangedTokensAndEmptyInputRoundTripExactly() {
        let input = "  👋 日本語\r\nprofessor\tperformance…  "
        #expect(TranscriptionVocabulary.correcting(input, terms: ["Profactor"]) == input)
        #expect(TranscriptionVocabulary.correcting("", terms: ["Danobat"]) == "")
    }
}
