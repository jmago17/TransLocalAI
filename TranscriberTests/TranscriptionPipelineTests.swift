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
#if canImport(WhisperKit)
import WhisperKit
#endif

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

    @Test @MainActor func transcriptBlocksParseTimestampsAndPlainLines() {
        let text = """
        [00:05] Welcome to the meeting.
        [1:23:45] Long recordings use hour stamps.
        A line without a timestamp.
        """
        let blocks = TranscriptPlayerView.parseBlocks(from: text)
        #expect(blocks.count == 3)
        #expect(blocks[0].time == 5)
        #expect(blocks[0].text == "Welcome to the meeting.")
        #expect(blocks[1].time == TimeInterval(1 * 3600 + 23 * 60 + 45))
        #expect(blocks[2].time == nil)
        #expect(blocks[2].text == "A line without a timestamp.")
    }

    @Test @MainActor func exportRoundTripsThroughImport() throws {
        let data = try #require(TranscriptionTerminology.exportJSON())
        let text = try #require(String(data: data, encoding: .utf8))
        // Everything exported already exists, so importing adds nothing.
        #expect(TranscriptionTerminology.importTerms(from: text) == 0)
    }
}

/// Fixes from the 2026-11-23 comparison against Quick Subs.
struct TranscriptionRobustnessTests {

    private func segment(_ start: Double, _ end: Double, _ text: String) -> WhisperDecodingSupport.Segment {
        WhisperDecodingSupport.Segment(start: start, end: end, text: text)
    }

    #if canImport(WhisperKit)
    /// Without a fixed language WhisperKit prefills <|en|> unless asked to
    /// detect: "multilingual" used to come out as English.
    @Test func noFixedLanguageAsksWhisperToDetectIt() {
        #expect(WhisperDecodingSupport.makeOptions(language: nil, profile: .balanced).detectLanguage)
        #expect(WhisperDecodingSupport.relaxedOptions(language: nil).detectLanguage)
        #expect(!WhisperDecodingSupport.makeOptions(language: "es", profile: .balanced).detectLanguage)
    }
    #endif

    @Test func languageVerdictNeedsARealSecondLanguage() {
        #expect(WhisperDecodingSupport.languageVerdict(votes: [:]) == nil)
        #expect(WhisperDecodingSupport.languageVerdict(votes: ["es": 8]) == "es")
        // One stray window out of eight is noise, not a second language.
        #expect(WhisperDecodingSupport.languageVerdict(votes: ["es": 7, "pt": 1]) == "es")
        #expect(WhisperDecodingSupport.languageVerdict(votes: ["eu": 5, "es": 3]) == "multilingual")
        #expect(WhisperDecodingSupport.languageVerdict(votes: ["es": 6, "eu": 2]) == "multilingual")
        // Too short to tell noise from a second language: stay open.
        #expect(WhisperDecodingSupport.languageVerdict(votes: ["es": 1, "eu": 1]) == "multilingual")
    }

    @Test func surveyWindowsSpreadOverTheWholeRecording() {
        let starts = WhisperDecodingSupport.surveyWindowStarts(duration: 2700, count: 8)
        #expect(starts.count == 8)
        #expect(starts.first! > 60)             // not just the opening
        #expect(starts.last! > 2400)
        #expect(starts.allSatisfy { $0 >= 0 && $0 <= 2670 })
        #expect(WhisperDecodingSupport.surveyWindowStarts(duration: 20, count: 4) == [0])
    }

    @Test func emptyAndSparseSegmentsDoNotCountAsCoverage() {
        let covering = WhisperDecodingSupport.coveringSpeech([
            segment(0, 5, "Hola, buenos días."),
            segment(100, 123, "-"),
            segment(200, 222, "Eta..."),
        ])
        #expect(covering.count == 2)
        #expect(covering[1].end == 202)
        let gaps = WhisperDecodingSupport.detectGaps(segments: covering, totalDuration: 230)
        #expect(gaps.count == 2)                // 5–200 and 202–230
    }

    @Test func recoveredTextInThePaddingIsNotMerged() {
        let primary = [segment(0, 10, "antes"), segment(40, 50, "después")]
        let recovered = [segment(10.2, 11.5, "eco del vecino"), segment(20, 25, "lo que faltaba")]
        let merged = WhisperDecodingSupport.merge(primary: primary, recovered: recovered, gap: 12...38)
        #expect(merged.map(\.text) == ["antes", "lo que faltaba", "después"])
    }

    @Test func loopsAreSeenThroughCaseAndPunctuation() {
        #expect(WhisperDecodingSupport.isRepetitionLoop("-Baina baina baina baina baina baina"))
    }

    @Test func collapsesDecoderLoopsButNotSpeech() {
        let loop = "-Baina ez " + Array(repeating: "baina", count: 100).joined(separator: " ")
        #expect(TranscriptSegments.collapseLoops(loop) == "-Baina ez baina")
        #expect(TranscriptSegments.collapseLoops("ya lo tienen, ya lo tienen, ya lo tienen, ya lo tienen. Sí.") == "ya lo tienen, Sí.")
        // Ordinary repetition stays.
        #expect(TranscriptSegments.collapseLoops("no, no, no, no") == "no, no, no, no")
        #expect(TranscriptSegments.collapseLoops("ya queda poco, ya queda poco") == "ya queda poco, ya queda poco")
        #expect(TranscriptSegments.collapseLoops("regular, la verdad que regular") == "regular, la verdad que regular")
    }

    @Test func sameLineThreeTimesInARowIsKeptOnce() {
        let repeated = (0..<3).map { TranscriptSegments.Segment(start: Double($0) * 2, end: Double($0) * 2 + 2, text: "It's on the bottom.") }
        let twice = (0..<2).map { TranscriptSegments.Segment(start: 10 + Double($0) * 2, end: 12 + Double($0) * 2, text: "Vale, vale, adelante.") }
        let kept = TranscriptSegments.dropRepeatedSegments(repeated + twice)
        #expect(kept.map(\.text) == ["It's on the bottom.", "Vale, vale, adelante.", "Vale, vale, adelante."])
    }

    @Test func rewordedEchoOfOnePhraseIsKeptOnce() {
        let lines = [
            "¿Esta es la pregunta?", "Esta es la pregunta.", "Si yo le hago la pregunta, igual iré a la pregunta.",
            "En principio, este es la pregunta.", "A ver, ahora nos vamos a dar la pregunta.", "Vale, seguimos.",
            "Ahora vamos a ir a la esta.", "Ya está, ahora vamos a ir a la asistencia.", "Vamos a ir a la luz.",
            "Ahora vamos a ir a la luz de la luz.", "Otra cosa.",
            // Three in a row is still speech.
            "Lo vemos en la reunión.", "Lo cerramos en la reunión.", "Y lo apuntamos en la reunión."
        ]
        let segments = lines.enumerated().map { TranscriptSegments.Segment(start: Double($0.offset) * 3, end: Double($0.offset) * 3 + 3, text: $0.element) }
        #expect(TranscriptSegments.dropEchoedSegments(segments).map(\.text) == [
            "¿Esta es la pregunta?", "Vale, seguimos.", "Ahora vamos a ir a la esta.", "Otra cosa.",
            "Lo vemos en la reunión.", "Lo cerramos en la reunión.", "Y lo apuntamos en la reunión."
        ])
    }

    @Test func strayLanguagesAreTheOnesWithNoRealShare() {
        func spoken(_ start: Double, _ end: Double, _ language: String?) -> WhisperDecodingSupport.Segment {
            WhisperDecodingSupport.Segment(start: start, end: end, text: "texto", language: language)
        }
        let segments = [
            spoken(0, 600, "es"), spoken(600, 900, "eu"), spoken(900, 905, "en"), spoken(906, 912, "en"),
            spoken(912, 1500, "es"), spoken(1500, 1502, "ru"), spoken(1502, 1510, nil)
        ]
        let languages = WhisperDecodingSupport.spokenLanguages(segments)
        #expect(languages == ["es", "eu"])
        #expect(WhisperDecodingSupport.strayLanguageRanges(segments, spoken: languages) == [900...912, 1500...1502])
        #expect(WhisperDecodingSupport.strayLanguageRanges(segments, spoken: []).isEmpty)
        #expect(WhisperDecodingSupport.languageToken(in: "<|startoftranscript|><|eu|><|transcribe|><|0.00|> Kaixo") == "eu")
        #expect(WhisperDecodingSupport.languageToken(in: "<|0.00|> Kaixo<|2.00|>") == nil)
    }

    @Test func wordsInAnotherScriptAreRemoved() {
        let latin = (0..<20).map { segment(Double($0), Double($0) + 1, "esto es una frase normal") }
        let cleaned = WhisperDecodingSupport.strippingStrayScripts(latin + [segment(30, 31, "ariko, baina, それから"), segment(32, 33, "Спасибо.")])
        #expect(cleaned[20].text == "ariko, baina,")
        #expect(cleaned[21].text.isEmpty)
        // A transcript in two scripts is left alone.
        let mixed = [segment(0, 1, "hola qué tal"), segment(1, 2, "Спасибо большое")]
        #expect(WhisperDecodingSupport.strippingStrayScripts(mixed).map(\.text) == mixed.map(\.text))
    }
}
