//
//  TranscriptionPipelineTests.swift
//  TranscriberTests
//
//  Tests for the shared Whisper decoding support (gap detection, merging,
//  hallucination filtering) and the terminology ranking layer.
//

import Testing
import Foundation
@testable import Transcriber

struct WhisperDecodingSupportTests {

    private func segment(_ start: Double, _ end: Double, _ text: String = "x") -> WhisperDecodingSupport.Segment {
        WhisperDecodingSupport.Segment(start: start, end: end, text: text)
    }

    @Test func detectsLeadingMiddleAndTrailingGaps() {
        let segments = [segment(15, 20), segment(40, 50)]
        let gaps = WhisperDecodingSupport.detectGaps(segments: segments, totalDuration: 100, minimumGap: 10)
        #expect(gaps.count == 3)
        #expect(gaps[0] == 0.0...15.0)
        #expect(gaps[1] == 20.0...40.0)
        #expect(gaps[2] == 50.0...100.0)
    }

    @Test func ignoresShortGaps() {
        let segments = [segment(0, 20), segment(25, 60)]
        let gaps = WhisperDecodingSupport.detectGaps(segments: segments, totalDuration: 62, minimumGap: 10)
        #expect(gaps.isEmpty)
    }

    @Test func fullCoverageHasNoGaps() {
        let segments = [segment(0, 30), segment(30, 60)]
        #expect(WhisperDecodingSupport.detectGaps(segments: segments, totalDuration: 60).isEmpty)
    }

    @Test func mergeKeepsRecoveredSegmentsOnlyInHoles() {
        let primary = [segment(0, 20, "kept"), segment(40, 60, "kept")]
        let recovered = [
            segment(5, 15, "overlaps primary"),      // dropped: inside primary
            segment(22, 38, "fills the hole")         // kept
        ]
        let merged = WhisperDecodingSupport.merge(primary: primary, recovered: recovered)
        #expect(merged.count == 3)
        #expect(merged[1].text == "fills the hole")
        #expect(merged.map(\.start) == merged.map(\.start).sorted())
    }

    @Test func mergeDropsRepetitionLoops() {
        let primary = [segment(0, 20, "kept")]
        let recovered = [segment(30, 50, "thank you thank you thank you thank you thank you thank you")]
        let merged = WhisperDecodingSupport.merge(primary: primary, recovered: recovered)
        #expect(merged.count == 1)
    }

    @Test func repetitionLoopDetection() {
        #expect(WhisperDecodingSupport.isRepetitionLoop("yes yes yes yes yes yes"))
        #expect(WhisperDecodingSupport.isRepetitionLoop("thank you thank you thank you thank you"))
        #expect(!WhisperDecodingSupport.isRepetitionLoop("the machine needs a new spindle before Friday"))
        #expect(!WhisperDecodingSupport.isRepetitionLoop("short text"))
    }

    @Test func metricsComputeCoverageAndGaps() {
        let segments = [segment(0, 30), segment(50, 80)]
        let metrics = WhisperDecodingSupport.computeMetrics(
            segments: segments,
            totalDuration: 100,
            processingTime: 25,
            profile: .balanced,
            retriedGaps: 1,
            recoveredSegments: 2
        )
        #expect(metrics.coveredSeconds == 60)
        #expect(metrics.coveragePercent == 60)
        #expect(metrics.gapCount == 2)  // 30–50 and 80–100
        #expect(metrics.gapSeconds == 40)
        #expect(metrics.realtimeFactor == 4)
    }
}

struct TranscriptionTerminologyTests {

    @Test @MainActor func rankedTermsExcludeDisabledAndPreferCorrected() {
        // Built-ins participate; a corrected term must outrank any built-in.
        TranscriptionTerminology.recordCorrection(canonical: "Wallix", variant: "Wallace")
        let ranked = TranscriptionTerminology.rankedTerms(limit: 10)
        #expect(ranked.first == "Wallix")

        TranscriptionTerminology.setEnabled(false, canonical: "Wallix")
        #expect(!TranscriptionTerminology.rankedTerms(limit: 100).contains("Wallix"))
        TranscriptionTerminology.setEnabled(true, canonical: "Wallix")
    }

    @Test @MainActor func whisperPromptStaysSmall() {
        #expect(TranscriptionTerminology.whisperPromptTerms().count <= 16)
        #expect(TranscriptionTerminology.appleContextualStrings().count <= 60)
    }

    @Test func normalizationFoldsCaseAndDiacritics() {
        #expect(TranscriptionTerminology.normalize("Iñaki") == TranscriptionTerminology.normalize("inaki"))
        #expect(TranscriptionTerminology.normalize("Active Directory") == "activedirectory")
    }

    @Test @MainActor func addUpdateAndDeleteTerm() {
        TranscriptionTerminology.addTerm("Tecnatom")
        #expect(TranscriptionTerminology.entries.contains { $0.canonical == "Tecnatom" && $0.source != .builtIn })

        TranscriptionTerminology.updateTerm(
            originalCanonical: "Tecnatom", newCanonical: "Tecnatom", aliases: ["Technatom"]
        )
        #expect(TranscriptionTerminology.entries.first { $0.canonical == "Tecnatom" }?.aliases == ["Technatom"])

        TranscriptionTerminology.deleteTerm(canonical: "Tecnatom")
        #expect(!TranscriptionTerminology.entries.contains { $0.canonical == "Tecnatom" && $0.source != .builtIn })
    }

    @Test @MainActor func importsPlainTextAndSkipsDuplicates() {
        TranscriptionTerminology.deleteTerm(canonical: "Profactor GmbH")
        let added = TranscriptionTerminology.importTerms(from: "Profactor GmbH = Perfactor\nDanobat\n")
        #expect(added == 1)  // Danobat is already a default term
        let entry = TranscriptionTerminology.entries.first { $0.canonical == "Profactor GmbH" }
        #expect(entry?.aliases == ["Perfactor"])
        // Re-import is a no-op
        #expect(TranscriptionTerminology.importTerms(from: "Profactor GmbH") == 0)
        TranscriptionTerminology.deleteTerm(canonical: "Profactor GmbH")
    }

    @Test @MainActor func exportRoundTripsThroughImport() throws {
        let data = try #require(TranscriptionTerminology.exportJSON())
        let text = try #require(String(data: data, encoding: .utf8))
        // Everything exported already exists, so importing adds nothing.
        #expect(TranscriptionTerminology.importTerms(from: text) == 0)
    }
}
