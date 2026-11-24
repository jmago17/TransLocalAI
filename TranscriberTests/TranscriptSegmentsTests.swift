import Foundation
import Testing
@testable import Transcriber

/// T4 (segment cleanup) and T5 (SRT/WebVTT export).
struct TranscriptSegmentsTests {
    typealias Segment = TranscriptSegments.Segment

    private func words(_ segments: [Segment]) -> [String] {
        segments.flatMap { $0.text.split(separator: " ").map(String.init) }
    }

    // MARK: - T4

    @Test func dropsEmptyAndPunctuationOnlyLines() {
        let tidy = TranscriptSegments.tidy([
            Segment(start: 0, end: 4, text: "We start with the stations today."),
            Segment(start: 111, end: 112, text: "."),
            Segment(start: 113, end: 114, text: " … "),
            Segment(start: 115, end: 116, text: ""),
            Segment(start: 120, end: 125, text: "Then the network.")
        ])
        #expect(tidy.map(\.text) == ["We start with the stations today.", "Then the network."])
    }

    @Test func dropsLinesThatAreOnlySoundTags() {
        let tidy = TranscriptSegments.tidy([
            Segment(start: 57.4, end: 81.5, text: "*scoffs*"),         // 24 s, from the test meeting
            Segment(start: 81.5, end: 103.3, text: " *Sigh* "),
            Segment(start: 104, end: 105, text: "[Music]"),
            Segment(start: 106, end: 107, text: "(laughs) ♪"),
            Segment(start: 110, end: 114, text: "Hello, hello. (laughs) Welcome back.")
        ])
        #expect(tidy.map(\.text) == ["Hello, hello. (laughs) Welcome back."])
    }

    @Test func mergesShortLinesAcrossShortPausesOnly() {
        let tidy = TranscriptSegments.tidy([
            Segment(start: 10, end: 11, text: "Okay."),
            Segment(start: 11.5, end: 15, text: "So the OP10 station is ready."),
            Segment(start: 15.4, end: 16, text: "Perfect."),
            Segment(start: 20, end: 21, text: "Yes."),           // 4 s pause: stays alone
            Segment(start: 30, end: 33, text: "Next topic is the archive.")
        ])
        #expect(tidy.map(\.text) == [
            "Okay. So the OP10 station is ready. Perfect.",
            "Yes.",
            "Next topic is the archive."
        ])
        #expect(tidy[0].start == 10 && tidy[0].end == 16)
    }

    @Test func doesNotMergePastTwentyWordsOrTwelveSeconds() {
        // Distinct words: the same word 19 times is a decoder loop and gets collapsed.
        let long = (1...19).map { "word\($0)" }.joined(separator: " ")
        let tidy = TranscriptSegments.tidy([
            Segment(start: 0, end: 8, text: long),
            Segment(start: 8.2, end: 9, text: "Okay then."),
        ])
        #expect(tidy.count == 2)
    }

    @Test func splitsLongSegmentsAtSentencesKeepingEveryWord() {
        let text = "First we check the network settings on both machines. Then we confirm that NTP is configured. " +
            "After that the DHCP lease is checked. Finally we run the first article inspection on the line."
        let input = [Segment(start: 1147, end: 1185, text: text)]   // the 38 s block at [19:07]
        let tidy = TranscriptSegments.tidy(input)
        #expect(tidy.count >= 4)
        #expect(tidy.allSatisfy { $0.end - $0.start <= TranscriptSegments.maxSegmentSeconds + 0.001 })
        #expect(words(tidy) == words(input))
        #expect(tidy.first?.start == 1147 && tidy.last?.end == 1185)
        for (a, b) in zip(tidy, tidy.dropFirst()) { #expect(a.end <= b.start + 0.001) }
    }

    @Test func splitsUnpunctuatedSegmentsByWords() {
        let text = (1...60).map { "w\($0)" }.joined(separator: " ")
        let input = [Segment(start: 0, end: 40, text: text)]
        let tidy = TranscriptSegments.tidy(input)
        #expect(tidy.count >= 4)
        #expect(tidy.allSatisfy { $0.end - $0.start <= TranscriptSegments.maxSegmentSeconds + 0.001 })
        #expect(words(tidy) == words(input))
    }

    @Test func renderDropsLinesTheCorrectionEmptiesWithTheirTiming() {
        let rendered = TranscriptSegments.render([
            Segment(start: 0, end: 3, text: "Keep this line please."),
            Segment(start: 65, end: 70, text: "remove me entirely now")
        ], correct: { $0.hasPrefix("remove") ? "" : $0 })
        #expect(rendered.text == "[00:00] Keep this line please.")
        #expect(rendered.timings == [.init(start: 0, end: 3)])
    }

    // MARK: - T5

    @Test func cuesUsePreciseTimingsAndFollowUserEdits() {
        let timings: [TranscriptSegments.Timing] = [
            .init(start: 5.25, end: 8.5), .init(start: 65.1, end: 69.9), .init(start: 130.4, end: 133)
        ]
        // The user edited line 2, deleted line 3 and added an unstamped line.
        let transcript = "[00:05] Hello Iñaki.\n[01:05] The OP20A station, edited.\nand a note added by hand"
        let cues = TranscriptSegments.cues(transcript: transcript, timings: timings, duration: 140)
        #expect(cues.count == 2)
        #expect(cues[0].start == 5.25 && cues[0].end == 8.5)
        #expect(cues[1].start == 65.1 && cues[1].end == 69.9)
        #expect(cues[1].lines.joined(separator: " ") == "The OP20A station, edited. and a note added by hand")
    }

    @Test func lastCueNeverPassesTheAudioDuration() {
        // Quick Subs ends at 28:16 on a 28:07 file; stored timings may overshoot.
        let timings: [TranscriptSegments.Timing] = [.init(start: 1680, end: 1696)]
        let cues = TranscriptSegments.cues(transcript: "[28:00] Thanks everyone, bye.", timings: timings, duration: 1687)
        #expect(cues.last.map { $0.end <= 1687 } == true)
    }

    @Test func legacyTranscriptsWithoutTimingsGetEstimatedNonOverlappingEnds() {
        let transcript = "[00:00] One two three four five.\n[00:02] Six seven.\n[00:30] Eight nine ten."
        let cues = TranscriptSegments.cues(transcript: transcript, timings: [], duration: 0)
        #expect(cues.count == 3)
        #expect(cues[0].end <= cues[1].start)
        #expect(cues[1].end <= 2 + 12)
        #expect(cues.allSatisfy { $0.end > $0.start })
    }

    @Test func longLinesBecomeSeveralTwoLineCues() {
        let text = (1...40).map { "palabra\($0)" }.joined(separator: " ")
        let cues = TranscriptSegments.cues(
            transcript: "[00:10] \(text)", timings: [.init(start: 10, end: 22)], duration: 60
        )
        #expect(cues.count > 1)
        #expect(cues.allSatisfy { $0.lines.count <= 2 && $0.lines.allSatisfy { $0.count <= 42 } })
        #expect(cues.flatMap { $0.lines.joined(separator: " ").split(separator: " ") }.count == 40)
        #expect(cues.first?.start == 10 && cues.last?.end == 22)
    }

    @Test func srtAndVttAreStructurallyValid() throws {
        let transcript = """
        [00:00] Good morning, this is the MTPL meeting.
        [00:04] .
        [00:05] Okay.
        [00:06] We review OP10, OP20A and the part data archive before the dry run on the VTP next week with Manfred and Martin.
        [1:00:02] Last line.
        """
        let timings: [TranscriptSegments.Timing] = [
            .init(start: 0.2, end: 3.9), .init(start: 5, end: 5.6), .init(start: 6, end: 14), .init(start: 3602, end: 3604)
        ]
        let cues = TranscriptSegments.cues(transcript: transcript, timings: timings, duration: 3603.5)
        try validateSRT(TranscriptSegments.srt(cues), duration: 3603.5)
        try validateVTT(TranscriptSegments.vtt(cues), duration: 3603.5)
        // And the app's own importer reads the text back.
        let imported = try TranscriptFileParser.text(from: Data(TranscriptSegments.srt(cues).utf8), extension: "srt")
        #expect(imported.contains("MTPL meeting") && imported.contains("Last line."))
        #expect(!imported.contains("-->"))
    }

    @Test func timecodesRoundToMilliseconds() {
        #expect(TranscriptSegments.timecode(3723.4567, separator: ",") == "01:02:03,457")
        #expect(TranscriptSegments.timecode(0, separator: ".") == "00:00:00.000")
    }

    // MARK: - Strict validators

    private struct Invalid: Error, CustomStringConvertible { let description: String }

    private func seconds(_ code: Substring, separator: Character) throws -> Double {
        let parts = code.split(separator: ":")
        guard parts.count == 3 else { throw Invalid(description: "bad timecode \(code)") }
        let secParts = parts[2].split(separator: separator)
        guard parts[0].count == 2, parts[1].count == 2, secParts.count == 2,
              secParts[0].count == 2, secParts[1].count == 3,
              let h = Double(parts[0]), let m = Double(parts[1]),
              let s = Double(secParts[0]), let ms = Double(secParts[1]), m < 60, s < 60
        else { throw Invalid(description: "bad timecode \(code)") }
        return h * 3600 + m * 60 + s + ms / 1000
    }

    private func validateCueBlocks(_ blocks: [Substring], separator: Character, numbered: Bool, duration: Double) throws {
        var previousEnd = 0.0
        for (index, block) in blocks.enumerated() {
            var lines = block.split(separator: "\n", omittingEmptySubsequences: false)
            if numbered {
                guard lines.first == Substring("\(index + 1)") else { throw Invalid(description: "bad index in \(block)") }
                lines.removeFirst()
            }
            guard let timing = lines.first else { throw Invalid(description: "missing timing") }
            let ends = timing.components(separatedBy: " --> ")
            guard ends.count == 2 else { throw Invalid(description: "bad timing line \(timing)") }
            let start = try seconds(Substring(ends[0]), separator: separator)
            let end = try seconds(Substring(ends[1]), separator: separator)
            guard end > start else { throw Invalid(description: "end before start: \(timing)") }
            guard start >= previousEnd - 0.0005 else { throw Invalid(description: "overlap at \(timing)") }
            guard end <= duration + 0.0005 else { throw Invalid(description: "past duration: \(timing)") }
            let text = lines.dropFirst()
            guard (1...2).contains(text.count), text.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                throw Invalid(description: "bad text in \(block)")
            }
            previousEnd = end
        }
    }

    private func validateSRT(_ srt: String, duration: Double) throws {
        #expect(srt.hasSuffix("\n"))
        let blocks = srt.trimmingCharacters(in: .newlines).components(separatedBy: "\n\n").map { Substring($0) }
        #expect(!blocks.isEmpty)
        try validateCueBlocks(blocks, separator: ",", numbered: true, duration: duration)
    }

    private func validateVTT(_ vtt: String, duration: Double) throws {
        #expect(vtt.hasPrefix("WEBVTT\n\n"))
        let body = vtt.dropFirst("WEBVTT\n\n".count)
        let blocks = body.trimmingCharacters(in: .newlines).components(separatedBy: "\n\n").map { Substring($0) }
        try validateCueBlocks(blocks, separator: ".", numbered: false, duration: duration)
    }
}
