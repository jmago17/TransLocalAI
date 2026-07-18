//
//  TranscriberTests.swift
//  TranscriberTests
//
//  Created by Josu Martinez Gonzalez on 15/12/25.
//

import Testing
import Foundation
@testable import Transcriber

struct TranscriberTests {

    @Test func importsSRTWithoutSequenceNumbersOrTimecodes() throws {
        let input = """
        1
        00:00:01,000 --> 00:00:03,000
        Welcome to Danobat.

        2
        00:00:04,000 --> 00:00:06,000
        Eneko owns the next action.
        """
        let output = try TranscriptFileParser.text(from: Data(input.utf8), extension: "srt")
        #expect(output == "Welcome to Danobat.\nEneko owns the next action.")
    }

    @Test func importsSegmentedJSON() throws {
        let input = #"{"segments":[{"text":"First"},{"text":"Second"}]}"#
        let output = try TranscriptFileParser.text(from: Data(input.utf8), extension: "json")
        #expect(output == "First\nSecond")
    }

    @Test @MainActor func correctsCloseSpecialTerms() {
        let output = TranscriptionVocabulary.correcting(
            "[00:19] We met perfactor yesterday.",
            terms: ["Profactor"]
        )
        #expect(output == "[00:19] We met Profactor yesterday.")
    }

    @Test @MainActor func keepsSentencePunctuationAfterReplacement() {
        let output = TranscriptionVocabulary.correcting(
            "We visited danobat. It went well.",
            terms: ["Danobat"]
        )
        #expect(output == "We visited Danobat. It went well.")
    }

    @Test @MainActor func replacesDeclaredMishearingsWithCanonicalSpelling() {
        let output = TranscriptionVocabulary.correcting(
            "Yankee and dinalan met at the office.",
            terms: ["Iñaki = Yankee, Ianki", "Dynamaz = Dinalan"]
        )
        #expect(output == "Iñaki and Dynamaz met at the office.")
    }

    @Test @MainActor func aliasLinesExposeOnlyCanonicalSpelling() {
        #expect(TranscriptionVocabulary.correcting(
            "We met inaki.",
            terms: ["Iñaki = Yankee"]
        ) == "We met Iñaki.")
    }

    @Test @MainActor func findsSuspiciousMidSentenceNames() {
        let suspects = TranscriptionVocabulary.suspiciousTerms(
            in: "[00:12] Yesterday we met Dinalan at the office.\nThen Danobat signed. So Gorosbel agreed too.",
            terms: ["Danobat", "Gorosabel"]
        )
        let words = suspects.map(\.word)
        #expect(words.contains("Dinalan"))
        #expect(!words.contains("Danobat"))       // known spelling
        #expect(!words.contains("Yesterday"))     // sentence start after timestamp
        #expect(!words.contains("Then"))          // sentence start
        #expect(suspects.first(where: { $0.word == "Gorosbel" })?.suggestion == "Gorosabel")
    }

    @Test @MainActor func leavesUnrelatedWordsUntouched() {
        let output = TranscriptionVocabulary.correcting(
            "The professor reviewed the performance.",
            terms: ["Profactor"]
        )
        #expect(output == "The professor reviewed the performance.")
    }

}
