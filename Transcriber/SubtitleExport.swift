import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// T5: SRT / WebVTT export of a transcript. The file is written only when
/// the user actually shares it, from the transcript as currently edited plus
/// the stored segment timings.
struct SubtitleExport: Transferable {
    enum Format: String, CaseIterable {
        case srt, vtt

        var label: String {
            switch self {
            case .srt: return String(localized: "Share Subtitles (SRT)")
            case .vtt: return String(localized: "Share Subtitles (WebVTT)")
            }
        }
    }

    let title: String
    let transcript: String
    let timings: Data?
    let duration: TimeInterval
    let format: Format

    init(transcription: Transcription, format: Format) {
        title = transcription.title
        transcript = transcription.transcriptionText
        timings = transcription.segmentTimings
        duration = transcription.duration
        self.format = format
    }

    /// False when no line carries a `[mm:ss]` stamp (nothing to time).
    static func isAvailable(for transcription: Transcription) -> Bool {
        transcription.transcriptionText
            .split(whereSeparator: \.isNewline)
            .contains { TranscriptSegments.parseStamped(String($0).trimmingCharacters(in: .whitespaces)) != nil }
    }

    var contents: String {
        let cues = TranscriptSegments.cues(
            transcript: transcript,
            timings: TranscriptSegments.decode(timings),
            duration: duration
        )
        switch format {
        case .srt: return TranscriptSegments.srt(cues)
        case .vtt: return TranscriptSegments.vtt(cues)
        }
    }

    var fileName: String {
        let safe = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return "\(safe.isEmpty ? "Transcript" : safe).\(format.rawValue)"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("subtitles-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(export.fileName)
            try Data(export.contents.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
