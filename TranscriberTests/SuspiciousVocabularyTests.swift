import Foundation
import Testing
@testable import Transcriber

struct SuspiciousVocabularyTests {
    @Test func repeatedLowercaseNearKnownTermIsReviewable() {
        let text = "[00:09] We discussed busqueda today.\n[00:30] The busquda results arrived. Another busquda was mentioned."
        let suspects = TranscriptionVocabulary.suspiciousTerms(in: text, terms: ["busqueda"])
        let candidate = suspects.first { $0.word == "busquda" }
        #expect(candidate?.suggestion == "busqueda")
        #expect(candidate?.count == 2)
        #expect(candidate?.timestamp == "00:30")
        #expect(candidate?.hint == "Close to a vocabulary term also used here")
        #expect(!suspects.contains { $0.word == "busqueda" })
        #expect(text.contains("busquda")) // Detection does not edit the transcript.
    }

    @Test func uncorroboratedLowercaseAndCommonWordsStayQuiet() {
        let suspects = TranscriptionVocabulary.suspiciousTerms(
            in: "We found busquda in a discussion. The professor reviewed performance. Today we talked again.",
            terms: ["busqueda", "Profactor"]
        )
        #expect(suspects.isEmpty)
    }

    @Test func explicitAliasOffersSingleLowercaseWithoutGlobalSynonyms() {
        let text = "[01:04] We heard buscera at the meeting."
        let suspects = TranscriptionVocabulary.suspiciousTerms(in: text, terms: ["Busqueda: buscera"])
        #expect(suspects.count == 1)
        #expect(suspects.first?.word == "buscera")
        #expect(suspects.first?.suggestion == "Busqueda")
        #expect(suspects.first?.hint == "Matches a variant you added")
        #expect(TranscriptionVocabulary.suspiciousTerms(in: text, terms: []).isEmpty)
    }

    @Test func competingCloseTermsDoNotClaimLowercaseSuggestion() {
        let suspects = TranscriptionVocabulary.suspiciousTerms(
            in: "busquda is mentioned twice. Another busquda appears here.",
            terms: ["busqueda", "busquida"]
        )
        #expect(suspects.isEmpty)
    }

    @Test func midSentenceNamesRemainVisibleAndRankAboveUnsupportedTokens() {
        let suspects = TranscriptionVocabulary.suspiciousTerms(
            in: "[00:01] Today we saw Gorosbel. Then Dinalan spoke. Dinalan returned. A professor agreed.",
            terms: ["Gorosabel"]
        )
        #expect(suspects.first?.word == "Gorosbel")
        #expect(suspects.first?.suggestion == "Gorosabel")
        #expect(suspects.first?.timestamp == "00:01")
        #expect(suspects.first(where: { $0.word == "Dinalan" })?.count == 2)
        #expect(!suspects.contains { $0.word == "Today" || $0.word == "professor" })
    }

    @Test func sentenceStartNameNeedsIndependentEvidence() {
        let noEvidence = TranscriptionVocabulary.suspiciousTerms(
            in: "Gorosbel arrived. Gorosbel spoke. Today we waited. Today we left.",
            terms: ["Gorosabel"]
        )
        #expect(!noEvidence.contains { $0.word == "Gorosbel" || $0.word == "Today" })
        let supported = TranscriptionVocabulary.suspiciousTerms(
            in: "Gorosbel arrived. Gorosbel spoke. Later we met Gorosabel.",
            terms: ["Gorosabel"]
        )
        #expect(supported.first(where: { $0.word == "Gorosbel" })?.count == 2)
        #expect(supported.first(where: { $0.word == "Gorosbel" })?.suggestion == "Gorosabel")
    }
}
