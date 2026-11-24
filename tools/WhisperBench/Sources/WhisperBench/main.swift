import AVFoundation
import CoreML
import Foundation
import WhisperKit

// Evaluation bench (see README.md). Runs the app's own Whisper pipeline —
// the Core files are symlinked, not copied — on one audio file and writes
// eval_report.md plus the transcript and subtitles to an output folder
// outside the repo. Only network use: the one-time model download.

/// Referenced by WhisperDecodingSupport.extractSlice; the app defines it in
/// TranscriptionEngine.swift, which the bench does not compile.
enum TranscriptionEngineError: Error { case invalidAudio, unsupportedLanguage(String) }

struct BenchError: Error, CustomStringConvertible { let description: String }

let env = ProcessInfo.processInfo.environment

func expand(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
}

func readLines(_ path: String?) throws -> [String]? {
    guard let path, !path.isEmpty else { return nil }
    return try String(contentsOf: expand(path), encoding: .utf8)
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}

// MARK: - Configuration

// BENCH_RETIDY=whisper_segments.txt: run only the segment clean-up (T4) on a
// previous run's raw segments and print the lines it drops. No model, no audio.
if let retidy = env["BENCH_RETIDY"], !retidy.isEmpty {
    let segments: [TranscriptSegments.Segment] = (try readLines(retidy) ?? []).compactMap { line in
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 3, let start = Double(parts[0]), let end = Double(parts[1]) else { return nil }
        return TranscriptSegments.Segment(start: start, end: end, text: parts[2])
    }
    let kept = TranscriptSegments.dropEchoedSegments(segments)
    let keptStarts = Set(kept.map(\.start))
    for segment in segments {
        print("\(keptStarts.contains(segment.start) ? " " : "X") \(TranscriptSegments.stamp(segment.start)) \(segment.text)")
    }
    print("\(segments.count - kept.count) of \(segments.count) segments dropped as echoes")
    exit(0)
}

guard let audioPath = env["BENCH_AUDIO"], !audioPath.isEmpty else {
    print("Usage: BENCH_AUDIO=/path/to/audio.m4a swift run -c release WhisperBench")
    print("Optional: BENCH_OUT, BENCH_LANGUAGE, BENCH_PROFILE, BENCH_VOCABULARY, BENCH_WATCH, BENCH_MODEL_BASE, BENCH_LABEL")
    exit(2)
}
let audioURL = expand(audioPath)
let modelId = env["BENCH_MODEL"] ?? "openai_whisper-large-v3-v20240930_626MB"
let modelBase = expand(env["BENCH_MODEL_BASE"] ?? "~/Library/Caches/TransLocalAI-WhisperBench")
let label = env["BENCH_LABEL"] ?? ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
let outDir = expand(env["BENCH_OUT"] ?? "~/Developer/TransLocalAI-eval").appendingPathComponent(label, isDirectory: true)
// The app's default for recordings is "multilingual": no fixed language.
// BENCH_LANGUAGE=detect runs the app's language survey first, as "auto-detect" does.
let detectFirst = env["BENCH_LANGUAGE"] == "detect"
var language = env["BENCH_LANGUAGE"].flatMap { $0.isEmpty || $0 == "multilingual" || $0 == "detect" ? nil : $0 }
let profile = env["BENCH_PROFILE"].flatMap(WhisperDecodingSupport.Profile.init(rawValue:)) ?? .balanced

// Vocabulary: a file in the app's line format ("Canonical: alias, alias"), or
// the app's built-in defaults. The bench never reads or writes the app's
// stored vocabulary.
let vocabularyFile = try readLines(env["BENCH_VOCABULARY"])
let vocabulary = vocabularyFile ?? TranscriptionTerminology.activeVocabularyLines
let promptTerms: [String] = vocabularyFile.map { lines in
    Array(lines.map { $0.components(separatedBy: ":")[0].trimmingCharacters(in: .whitespaces) }.prefix(16))
} ?? TranscriptionTerminology.whisperPromptTerms()
// Watch list: spellings to count (right ones and known mishearings).
let watchTerms = try readLines(env["BENCH_WATCH"]) ?? []

guard FileManager.default.fileExists(atPath: audioURL.path) else {
    throw BenchError(description: "Audio not found: \(audioURL.path)")
}
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: modelBase, withIntermediateDirectories: true)

// BENCH_ENGINE=apple: the engine "Auto" picks for every language but Basque
// and multilingual. Runs the app's SpeechTranscriptionManager as is (its
// output skips T4) and writes only the transcript; BENCH_LANGUAGE is a
// locale such as es-ES.
if env["BENCH_ENGINE"] == "apple" {
    let locale = env["BENCH_LANGUAGE"] ?? "es-ES"
    print("Transcribing \(audioURL.lastPathComponent) [Apple Speech, \(locale)]…")
    let started = Date()
    let text = try await SpeechTranscriptionManager().transcribe(audioURL: audioURL, language: locale)
    try text.write(to: outDir.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
    print(String(format: "Done in %.0f s: %@", Date().timeIntervalSince(started), outDir.appendingPathComponent("transcript.txt").path))
    exit(0)
}

// MARK: - Model

let expectedFolder = modelBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(modelId)", isDirectory: true)
let modelFolder: URL
if WhisperLocalModels.isComplete(expectedFolder) {
    modelFolder = expectedFolder
} else {
    print("Downloading \(modelId) to \(modelBase.path) (one time)…")
    modelFolder = try await WhisperKit.download(variant: modelId, downloadBase: modelBase)
}

print("Loading model…")
let loadStart = Date()
let whisper = try await WhisperKit(WhisperKitConfig(
    modelFolder: modelFolder.path,
    tokenizerFolder: modelBase,
    computeOptions: ModelComputeOptions(          // same as the app
        melCompute: .cpuOnly,
        audioEncoderCompute: .cpuAndNeuralEngine,
        textDecoderCompute: .cpuAndNeuralEngine,
        prefillCompute: .cpuOnly
    ),
    download: false
))
let loadSeconds = Date().timeIntervalSince(loadStart)

if detectFirst {
    let votes = await WhisperDecodingSupport.surveyLanguages(whisper: whisper, audioURL: audioURL)
    let verdict = WhisperDecodingSupport.languageVerdict(votes: votes)
    print("Language survey: \(votes.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")) → \(verdict ?? "none")")
    language = verdict.flatMap { $0 == "multilingual" ? nil : $0 }
}

// MARK: - Run

print("Transcribing \(audioURL.lastPathComponent) [\(profile.rawValue), language \(language ?? "auto")]…")
let output = try await WhisperDecodingSupport.runPipeline(
    whisper: whisper,
    audioURL: audioURL,
    language: language,
    profile: profile,
    gapPolicy: .app(profile),
    vocabulary: vocabulary,
    adjustOptions: { options in
        // Experiments; unset means exactly the app's options.
        // The app sends no prompt; BENCH_GLOSSARY_PROMPT=1 restores the old
        // "Glossary: …" prompt for comparison.
        if env["BENCH_GLOSSARY_PROMPT"] == "1", let tokenizer = whisper.tokenizer {
            options.promptTokens = WhisperDecodingSupport.promptTokens(tokenizer: tokenizer, terms: promptTerms)
        }
        if let text = env["BENCH_PROMPT_TEXT"], let tokenizer = whisper.tokenizer {
            options.promptTokens = tokenizer.encode(text: " " + text)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        if env["BENCH_CHUNKING"] == "none" { options.chunkingStrategy = ChunkingStrategy.none }
        if let value = env["BENCH_NO_SPEECH"].flatMap(Float.init) { options.noSpeechThreshold = value }
        if let value = env["BENCH_LOGPROB"].flatMap(Float.init) { options.logProbThreshold = value }
    }
)
let metrics = output.metrics

// Probe: what relaxed decoding finds in the gaps the app did NOT retry.
// Diagnostic only — not part of the app run, not in the processing time.
let skippedGaps = output.gaps.filter { gap in !output.retriedGaps.contains(gap) }
var probes: [(gap: ClosedRange<Double>, text: String)] = []
if env["BENCH_PROBE_GAPS"] != "0" {
    for gap in skippedGaps {
        guard let slice = try? await WhisperDecodingSupport.extractSlice(from: audioURL, range: gap) else { continue }
        let results = (try? await whisper.transcribe(
            audioPath: slice.url.path, decodeOptions: WhisperDecodingSupport.relaxedOptions(language: language)
        )) ?? []
        let found = WhisperDecodingSupport.segments(from: results.flatMap(\.segments), offset: slice.offset)
            .filter { $0.end > gap.lowerBound && $0.start < gap.upperBound }
        probes.append((gap, found.map(\.text).joined(separator: " ")))
        try? FileManager.default.removeItem(at: slice.url)
    }
}
let duration = metrics.audioDuration

// MARK: - Analysis

extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

func words(_ text: String) -> [Substring] { text.split(whereSeparator: \.isWhitespace) }

let lines: [(start: Int, text: String)] = output.text.components(separatedBy: "\n").compactMap {
    TranscriptSegments.parseStamped($0)
}
let lineDurations = output.timings.map { $0.end - $0.start }
let normalizedLines = lines.map { TranscriptionTerminology.normalize($0.text) }
let consecutiveDuplicates = zip(normalizedLines, normalizedLines.dropFirst()).filter { $0 == $1 && !$0.isEmpty }.count
let loopLines = lines.filter { WhisperDecodingSupport.isRepetitionLoop($0.text) }
let rawLoops = output.rawSegments.filter { WhisperDecodingSupport.isRepetitionLoop($0.text) }
let rawPunctuationOnly = output.rawSegments.filter { !TranscriptSegments.hasSpokenContent($0.text) }.count
let rawLong = output.rawSegments.filter { $0.end - $0.start > TranscriptSegments.maxSegmentSeconds }
let rawLongest = output.rawSegments.map { $0.end - $0.start }.max() ?? 0

/// A line mostly made of prompt terms is the decoder echoing its prompt.
let promptKeys = Set(promptTerms.map { TranscriptionTerminology.normalize($0) }.filter { !$0.isEmpty })
let promptEchoes = lines.filter { line in
    let hits = promptKeys.filter { line.text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }.count
    return hits >= 3 && hits * 3 >= words(line.text).count
}

func occurrences(of term: String, in text: String) -> Int {
    let escaped = NSRegularExpression.escapedPattern(for: term)
    guard let regex = try? NSRegularExpression(
        pattern: "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])", options: [.caseInsensitive]
    ) else { return 0 }
    return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
}
let rawText = output.rawSegments.map(\.text).joined(separator: "\n")

// Subtitles, validated with the same rules as the unit tests.
let cues = TranscriptSegments.cues(transcript: output.text, timings: output.timings, duration: duration)
let srt = TranscriptSegments.srt(cues)
let vtt = TranscriptSegments.vtt(cues)

func seconds(_ code: String, separator: Character) -> Double? {
    let parts = code.split(separator: ":")
    guard parts.count == 3 else { return nil }
    let sec = parts[2].split(separator: separator)
    guard parts[0].count == 2, parts[1].count == 2, sec.count == 2, sec[0].count == 2, sec[1].count == 3,
          let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(sec[0]), let ms = Double(sec[1]),
          m < 60, s < 60 else { return nil }
    return h * 3600 + m * 60 + s + ms / 1000
}

func validate(_ document: String, header: String?, separator: Character, numbered: Bool) -> String? {
    var body = Substring(document)
    if let header {
        guard body.hasPrefix(header) else { return "missing \(header.trimmingCharacters(in: .newlines)) header" }
        body = body.dropFirst(header.count)
    }
    guard document.hasSuffix("\n") else { return "no trailing newline" }
    var previousEnd = 0.0
    for (index, block) in body.trimmingCharacters(in: .newlines).components(separatedBy: "\n\n").enumerated() {
        var blockLines = block.components(separatedBy: "\n")
        if numbered {
            guard blockLines.first == "\(index + 1)" else { return "cue \(index + 1): bad number" }
            blockLines.removeFirst()
        }
        let ends = (blockLines.first ?? "").components(separatedBy: " --> ")
        guard ends.count == 2, let start = seconds(ends[0], separator: separator),
              let end = seconds(ends[1], separator: separator) else { return "cue \(index + 1): bad timing line" }
        guard end > start else { return "cue \(index + 1): ends before it starts" }
        guard start >= previousEnd - 0.0005 else { return "cue \(index + 1): overlaps the previous one" }
        guard end <= duration + 0.0005 else { return "cue \(index + 1): ends after the audio" }
        let text = blockLines.dropFirst()
        guard (1...2).contains(text.count), text.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return "cue \(index + 1): needs 1–2 text lines" }
        previousEnd = end
    }
    return nil
}
let srtProblem = validate(srt, header: nil, separator: ",", numbered: true)
let vttProblem = validate(vtt, header: "WEBVTT\n\n", separator: ".", numbered: false)
let longestCueLine = cues.flatMap(\.lines).map(\.count).max() ?? 0

// MARK: - Comparison with the previous run

struct Summary: Codable {
    var label: String
    var processingTime: Double
    var realtimeFactor: Double
    var coveragePercent: Double
    var lines: Int
    var linesOver12s: Int
    var loopLines: Int
    var promptEchoes: Int
    var watch: [String: Int]
}
let summary = Summary(
    label: label,
    processingTime: metrics.processingTime,
    realtimeFactor: metrics.realtimeFactor,
    coveragePercent: metrics.coveragePercent,
    lines: lines.count,
    linesOver12s: lineDurations.filter { $0 > TranscriptSegments.maxSegmentSeconds + 0.001 }.count,
    loopLines: loopLines.count,
    promptEchoes: promptEchoes.count,
    watch: Dictionary(uniqueKeysWithValues: watchTerms.map { ($0, occurrences(of: $0, in: output.text)) })
)
let baselineURL = outDir.deletingLastPathComponent().appendingPathComponent("baseline.json")
let baseline = (try? Data(contentsOf: baselineURL)).flatMap { try? JSONDecoder().decode(Summary.self, from: $0) }

// MARK: - Report

func f(_ value: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", value) }
func clock(_ seconds: Double) -> String { TranscriptSegments.timecode(seconds, separator: ".") }
func delta(_ now: Double, _ before: Double?, _ digits: Int = 1) -> String {
    guard let before else { return "" }
    let change = now - before
    return " (\(change >= 0 ? "+" : "")\(f(change, digits)) vs \(baseline?.label ?? "baseline"))"
}

var report = """
# Evaluation report — \(label)

- Audio: `\(audioURL.lastPathComponent)`, \(clock(duration))
- Model: `\(modelId)`, WhisperKit ba09449, profile \(profile.rawValue), language \(language ?? "auto")
- Vocabulary: \(vocabularyFile == nil ? "app built-in defaults" : "file, \(vocabulary.count) lines"); \
Whisper prompt: \(env["BENCH_GLOSSARY_PROMPT"] == "1" ? "glossary of \(promptTerms.count) terms" : env["BENCH_PROMPT_TEXT"].map { "“\($0)”" } ?? "none (as the app)")
- Experiments: \(["BENCH_GLOSSARY_PROMPT", "BENCH_PROMPT_TEXT", "BENCH_CHUNKING", "BENCH_NO_SPEECH", "BENCH_LOGPROB"].compactMap { key in env[key].map { "\(key)=\($0)" } }.joined(separator: ", ").nilIfEmpty ?? "none (app options)")
- Machine: Mac (Neural Engine). **Timings on an iPhone will differ.**

## Speed
| | |
|---|---|
| Model load | \(f(loadSeconds)) s |
| Processing | \(f(metrics.processingTime)) s\(delta(metrics.processingTime, baseline?.processingTime)) |
| Speed | \(f(metrics.realtimeFactor))× real time |

## Whisper output (before cleanup)
| | |
|---|---|
| Segments | \(output.rawSegments.count) |
| Coverage | \(f(metrics.coveragePercent))%\(delta(metrics.coveragePercent, baseline?.coveragePercent)) |
| Gaps > 10 s | \(metrics.gapCount) (\(f(metrics.gapSeconds, 0)) s) |
| Main pass alone | \(output.primarySegments.count) segments, \(f(WhisperDecodingSupport.computeMetrics(segments: output.primarySegments, totalDuration: duration, processingTime: 0, profile: profile, retriedGaps: 0, recoveredSegments: 0).coveragePercent))% coverage |
| Gaps retried / segments recovered | \(metrics.retriedGaps) / \(metrics.recoveredSegments) |
| Punctuation-only segments | \(rawPunctuationOnly) |
| Segments > 12 s | \(rawLong.count) (longest \(f(rawLongest)) s) |
| Repetition loops | \(rawLoops.count) |

## Final transcript (after T4 and corrections)
| | |
|---|---|
| Lines | \(lines.count) |
| Lines > 12 s | \(summary.linesOver12s) (longest \(f(lineDurations.max() ?? 0)) s) |
| Lines of ≤ 3 words | \(lines.filter { words($0.text).count <= TranscriptSegments.shortSegmentWords }.count) |
| Consecutive duplicate lines | \(consecutiveDuplicates) |
| Repetition loops | \(loopLines.count) |
| Prompt echoes | \(promptEchoes.count) |
| Timings stored | \(output.timings.count == lines.count ? "yes, one per line" : "MISMATCH: \(output.timings.count) for \(lines.count) lines") |

## Subtitles
| | |
|---|---|
| Cues | \(cues.count) |
| SRT | \(srtProblem.map { "INVALID: \($0)" } ?? "valid") |
| WebVTT | \(vttProblem.map { "INVALID: \($0)" } ?? "valid") |
| Last cue ends | \(clock(cues.last?.end ?? 0)) (audio \(clock(duration))) |
| Longest subtitle line | \(longestCueLine) characters |

"""

if !watchTerms.isEmpty {
    report += "## Watch list\n| Spelling | Whisper | Final | Previous final |\n|---|---|---|---|\n"
    for term in watchTerms {
        let before = baseline?.watch[term].map(String.init) ?? "–"
        report += "| \(term) | \(occurrences(of: term, in: rawText)) | \(summary.watch[term] ?? 0) | \(before) |\n"
    }
    report += "\n"
}

func sample(_ title: String, _ items: [String]) {
    guard !items.isEmpty else { return }
    report += "### \(title)\n" + items.prefix(10).map { "- \($0)" }.joined(separator: "\n") + "\n\n"
}
func stamped(_ line: (start: Int, text: String)) -> String {
    "[\(TranscriptSegments.stamp(Double(line.start)))] \(line.text)"
}
report += "## Gaps after the main pass\n| Range | Length | Retried by the app | Relaxed decode finds |\n|---|---|---|---|\n"
for gap in output.gaps {
    let retried = output.retriedGaps.contains(gap)
    let probe = probes.first { $0.gap == gap }.map { $0.text.isEmpty ? "nothing" : "\(words($0.text).count) words: “\(words($0.text).prefix(12).joined(separator: " "))…”" }
    report += "| \(TranscriptSegments.stamp(gap.lowerBound))–\(TranscriptSegments.stamp(gap.upperBound)) | \(f(gap.upperBound - gap.lowerBound, 0)) s | \(retried ? "yes" : "**no**") | \(retried ? "(merged into the transcript)" : probe ?? "not probed") |\n"
}
report += "\n"

report += "## Examples\n"
sample("Repetition loops", loopLines.map(stamped))
sample("Prompt echoes", promptEchoes.map(stamped))
sample("Whisper segments over 12 s", rawLong.map { "[\(TranscriptSegments.stamp($0.start))] \(f($0.end - $0.start)) s" })
report += """
## Not measured
- Word error rate: there is no hand-corrected reference transcript.
- Speaker turns, summaries.

Files: `transcript.txt`, `whisper_segments.txt`, `subtitles.srt`, `subtitles.vtt`, `summary.json`.
To compare later runs against this one, copy `summary.json` to `../baseline.json`.

"""

// MARK: - Write

let rawDump = output.rawSegments.map { "\(f($0.start, 2))\t\(f($0.end, 2))\t\($0.text)\t\($0.language ?? "")" }.joined(separator: "\n")
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try report.write(to: outDir.appendingPathComponent("eval_report.md"), atomically: true, encoding: .utf8)
try output.text.write(to: outDir.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
try rawDump.write(to: outDir.appendingPathComponent("whisper_segments.txt"), atomically: true, encoding: .utf8)
try srt.write(to: outDir.appendingPathComponent("subtitles.srt"), atomically: true, encoding: .utf8)
try vtt.write(to: outDir.appendingPathComponent("subtitles.vtt"), atomically: true, encoding: .utf8)
try encoder.encode(summary).write(to: outDir.appendingPathComponent("summary.json"))
print("Report: \(outDir.appendingPathComponent("eval_report.md").path)")
