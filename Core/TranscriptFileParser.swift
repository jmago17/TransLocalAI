import Foundation

enum TranscriptFileParser {
    enum ParseError: LocalizedError {
        case unreadable
        var errorDescription: String? { "The selected file does not contain a readable transcript." }
    }

    static func text(from data: Data, extension fileExtension: String) throws -> String {
        if fileExtension.lowercased() == "json",
           let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any] {
            for key in ["transcript", "transcription", "text", "content"] {
                if let value = dictionary[key] as? String, !value.isEmpty { return value }
            }
            if let segments = dictionary["segments"] as? [[String: Any]] {
                let text = segments.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !text.isEmpty { return text }
            }
        }
        guard var string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw ParseError.unreadable
        }
        if ["srt", "vtt"].contains(fileExtension.lowercased()) {
            string = string.components(separatedBy: .newlines)
                .filter { line in
                    let clean = line.trimmingCharacters(in: .whitespaces)
                    return !clean.isEmpty && !clean.contains("-->") && Int(clean) == nil && clean != "WEBVTT"
                }
                .joined(separator: "\n")
        }
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ParseError.unreadable }
        return string
    }
}
