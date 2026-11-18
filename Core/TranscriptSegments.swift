import Foundation

/// Segment cleanup (T4) and subtitle export (T5).
///
/// Transcripts are stored as `[mm:ss] text` lines because that is what the
/// user reads and edits. Precise start/end times are stored alongside
/// (`Transcription.segmentTimings`) and matched back to lines by their
/// whole-second stamp, so subtitle export follows the user's edits to the
/// text while keeping the engine's timing. Pure and `nonisolated`: engines
/// call it from background tasks; the Share extension compiles it too.
nonisolated enum TranscriptSegments {

    struct Segment: Sendable, Equatable {
        var start: Double
        var end: Double
        var text: String
    }

    struct Timing: Codable, Sendable, Equatable {
        var start: Double
        var end: Double
    }

    // MARK: - T4: tidy

    /// Longest segment kept as one line (and one subtitle cue group).
    static let maxSegmentSeconds = 12.0
    /// Short lines merge with a neighbour only across a pause shorter than this.
    static let mergeGapSeconds = 1.5
    static let maxMergedWords = 20
    /// "Okay." / "Yes, perfect." — lines this short merge with a neighbour.
    static let shortSegmentWords = 3

    /// Drops empty and punctuation-only segments, splits segments longer
    /// than `maxSegmentSeconds`, and merges very short ones into a neighbour.
    /// Never drops a word: every word of a kept segment survives, in order.
    static func tidy(_ segments: [Segment]) -> [Segment] {
        let kept = segments
            .map { Segment(start: $0.start, end: max($0.end, $0.start), text: collapseWhitespace($0.text)) }
            .filter { hasSpokenContent($0.text) }
            .sorted { $0.start < $1.start }
        return mergeShort(kept.flatMap(splitLong))
    }

    /// False for "", ".", "…", "-" — lines with no letter or digit.
    static func hasSpokenContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func mergeShort(_ segments: [Segment]) -> [Segment] {
        var result: [Segment] = []
        for segment in segments {
            if var last = result.last,
               wordCount(last.text) <= shortSegmentWords || wordCount(segment.text) <= shortSegmentWords,
               segment.start - last.end < mergeGapSeconds,
               wordCount(last.text) + wordCount(segment.text) <= maxMergedWords,
               max(last.end, segment.end) - last.start <= maxSegmentSeconds {
                last.text += " " + segment.text
                last.end = max(last.end, segment.end)
                result[result.count - 1] = last
            } else {
                result.append(segment)
            }
        }
        return result
    }

    private enum SplitLevel {
        case sentence, clause, word

        var next: SplitLevel? {
            switch self {
            case .sentence: return .clause
            case .clause: return .word
            case .word: return nil
            }
        }
    }

    /// Splits at sentence ends, then at clause punctuation, then at words.
    /// Without word timestamps, times are shared out by character count.
    private static func splitLong(_ segment: Segment) -> [Segment] {
        split(segment, level: .sentence)
    }

    private static func split(_ segment: Segment, level: SplitLevel) -> [Segment] {
        let duration = segment.end - segment.start
        guard duration > maxSegmentSeconds else { return [segment] }

        let pieces: [String]
        switch level {
        case .sentence: pieces = splitPieces(of: segment.text, after: ".!?…")
        case .clause: pieces = splitPieces(of: segment.text, after: ",;:")
        case .word:
            let words = segment.text.split(separator: " ").map(String.init)
            let chunks = max(1, Int((duration / maxSegmentSeconds).rounded(.up)))
            let perChunk = max(1, Int((Double(words.count) / Double(chunks)).rounded(.up)))
            pieces = stride(from: 0, to: words.count, by: perChunk).map {
                words[$0..<min($0 + perChunk, words.count)].joined(separator: " ")
            }
        }
        guard pieces.count > 1 else {
            guard let next = level.next else { return [segment] }
            return split(segment, level: next)
        }

        // Group consecutive pieces while they fit in one segment.
        let timed = distribute(pieces, over: segment)
        var grouped: [Segment] = []
        for piece in timed {
            if var last = grouped.last, piece.end - last.start <= maxSegmentSeconds {
                last.text += " " + piece.text
                last.end = piece.end
                grouped[grouped.count - 1] = last
            } else {
                grouped.append(piece)
            }
        }
        guard let next = level.next else { return grouped }
        return grouped.flatMap { split($0, level: next) }
    }

    /// Splits after any of `marks` followed by a space; marks stay attached.
    private static func splitPieces(of text: String, after marks: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let nextIsSpace = index + 1 < characters.count && characters[index + 1] == " "
            if marks.contains(character), nextIsSpace {
                pieces.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces.filter { !$0.isEmpty }
    }

    private static func distribute(_ pieces: [String], over segment: Segment) -> [Segment] {
        let total = Double(pieces.reduce(0) { $0 + $1.count + 1 })
        let duration = segment.end - segment.start
        var cursor = segment.start
        return pieces.enumerated().map { index, piece in
            let share = total > 0 ? Double(piece.count + 1) / total : 0
            let end = index == pieces.count - 1 ? segment.end : cursor + duration * share
            defer { cursor = end }
            return Segment(start: cursor, end: end, text: piece)
        }
    }

    // MARK: - Stored lines + timings

    static func stamp(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    /// Tidies engine segments and renders them as the stored transcript:
    /// `[mm:ss] text` lines plus the matching precise timings. `correct` runs
    /// per line (vocabulary); a line it empties is dropped with its timing.
    static func render(
        _ segments: [Segment],
        correct: (String) -> String = { $0 }
    ) -> (text: String, timings: [Timing]) {
        var lines: [String] = []
        var timings: [Timing] = []
        for segment in tidy(segments) {
            let text = correct(segment.text).trimmingCharacters(in: .whitespaces)
            guard hasSpokenContent(text) else { continue }
            lines.append("[\(stamp(segment.start))] \(text)")
            timings.append(Timing(start: segment.start, end: segment.end))
        }
        return (lines.joined(separator: "\n"), timings)
    }

    static func encode(_ timings: [Timing]) -> Data? {
        timings.isEmpty ? nil : try? JSONEncoder().encode(timings)
    }

    static func decode(_ data: Data?) -> [Timing] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Timing].self, from: data)) ?? []
    }

    // MARK: - T5: subtitle cues

    struct Cue: Sendable, Equatable {
        var start: Double
        var end: Double
        /// One or two lines, already wrapped.
        var lines: [String]
    }

    static let maxLineCharacters = 42
    static let maxCueLines = 2
    /// Reading time used when a line has no stored end time.
    private static func estimatedSeconds(for text: String) -> Double {
        min(maxSegmentSeconds, max(1.5, Double(wordCount(text)) * 0.4 + 0.5))
    }

    /// Builds subtitle cues from the transcript as the user sees it.
    /// Stored timings supply precise start/end where a line's stamp matches;
    /// otherwise the end is estimated from the text and the next line.
    /// Every cue ends after it starts, before the next cue, and within
    /// `duration` (when known).
    static func cues(transcript: String, timings: [Timing], duration: Double) -> [Cue] {
        struct Line { var stamp: Int; var text: String }
        var lines: [Line] = []
        for raw in transcript.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let (seconds, text) = parseStamped(trimmed) {
                lines.append(Line(stamp: seconds, text: text))
            } else if !lines.isEmpty {
                // Unstamped line (user edit): continuation of the previous one.
                lines[lines.count - 1].text += " " + trimmed
            }
        }
        lines = lines.filter { hasSpokenContent($0.text) }
        guard !lines.isEmpty else { return [] }

        var byStamp: [Int: [Timing]] = [:]
        for timing in timings.sorted(by: { $0.start < $1.start }) {
            byStamp[Int(max(0, timing.start)), default: []].append(timing)
        }

        var timed: [Segment] = lines.map { line in
            if var queue = byStamp[line.stamp], !queue.isEmpty {
                let timing = queue.removeFirst()
                byStamp[line.stamp] = queue
                return Segment(start: timing.start, end: timing.end, text: collapseWhitespace(line.text))
            }
            let start = Double(line.stamp)
            return Segment(start: start, end: start + estimatedSeconds(for: line.text), text: collapseWhitespace(line.text))
        }
        timed.sort { $0.start < $1.start }

        let limit = duration > 0 ? duration : .infinity
        var cues: [Cue] = []
        for index in timed.indices {
            var segment = timed[index]
            let nextStart = index + 1 < timed.count ? timed[index + 1].start : limit
            segment.start = min(segment.start, limit)
            segment.end = min(segment.end, nextStart, limit)
            if segment.end <= segment.start {
                // Zero-length or inverted: give it a short slot if there is room.
                segment.end = min(segment.start + 1, nextStart, limit)
            }
            guard segment.end > segment.start else { continue }
            cues.append(contentsOf: splitIntoCues(segment))
        }
        return cues
    }

    /// `[mm:ss] text` or `[h:mm:ss] text` → (seconds, text).
    static func parseStamped(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let inside = line[line.index(after: line.startIndex)..<close]
        let parts = inside.split(separator: ":").map { Int($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        let values = parts.compactMap { $0 }
        let seconds = values.reduce(0) { $0 * 60 + $1 }
        let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return (seconds, text)
    }

    /// Splits a segment whose text does not fit in two 42-character lines
    /// into consecutive cues, sharing its time by character count.
    private static func splitIntoCues(_ segment: Segment) -> [Cue] {
        let words = segment.text.split(separator: " ").map(String.init)
        var chunks: [[String]] = [[]]
        for word in words {
            let candidate = chunks[chunks.count - 1] + [word]
            if !chunks[chunks.count - 1].isEmpty, wrap(candidate).count > maxCueLines {
                chunks.append([word])
            } else {
                chunks[chunks.count - 1] = candidate
            }
        }
        let texts = chunks.filter { !$0.isEmpty }.map { $0.joined(separator: " ") }
        return distribute(texts, over: segment).map { piece in
            Cue(start: piece.start, end: piece.end, lines: wrap(piece.text.split(separator: " ").map(String.init)))
        }
    }

    /// Greedy wrap at `maxLineCharacters`; a single longer word gets its own line.
    private static func wrap(_ words: [String]) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in words {
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= maxLineCharacters {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    // MARK: - Writers

    static func srt(_ cues: [Cue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timecode(cue.start, separator: ",")) --> \(timecode(cue.end, separator: ","))\n\(cue.lines.joined(separator: "\n"))\n"
        }.joined(separator: "\n")
    }

    static func vtt(_ cues: [Cue]) -> String {
        "WEBVTT\n\n" + cues.map { cue in
            "\(timecode(cue.start, separator: ".")) --> \(timecode(cue.end, separator: "."))\n\(cue.lines.joined(separator: "\n"))\n"
        }.joined(separator: "\n")
    }

    /// HH:MM:SS,mmm (SRT) or HH:MM:SS.mmm (WebVTT).
    static func timecode(_ seconds: Double, separator: String) -> String {
        let totalMilliseconds = Int((max(0, seconds) * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, secs, separator, milliseconds)
    }
}
