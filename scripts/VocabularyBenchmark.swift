// Compile with Core/TranscriptionVocabulary.swift using swiftc -O.
// Pass an existing output directory; compare fixture files against the baseline.
import Foundation

@main
enum VocabularyBenchmark {
    static func main() throws {

        let terms = ["Danobat", "Gorosabel", "Iñaki", "Profactor", "Ion Azpeitia"] + (0..<95).map { "TechnicalTerm\($0)" }
        let fixtures: [(String, String, [String])] = [
            ("decomposed", "danobat\u{301} danobat inaki\u{301}", ["Danobat", "Iñaki"]),
            ("unicode", "👩🏽‍💻 [00:19] inaki, INAKI; danobat.\n日本語: inaki — café!", ["Iñaki", "Danobat"]),
            ("aliases", "Yankee met ion azpeitia. Yankee!", ["Ianki: Yankee", "Iñaki = Ianki", "Ion Azpeitia"]),
            ("unchanged", "  👋 日本語\r\nprofessor\tperformance…  ", ["Profactor"]),
            ("repeated", String(repeating: "[00:19] We met gorosbel and danobat. The professor reviewed performance.\n", count: 500), terms),
            ("unique", (0..<2000).map { "item\($0)" }.joined(separator: " "), terms)
        ]
        for (name, input, vocabulary) in fixtures {
            let output = TranscriptionVocabulary.correcting(input, terms: vocabulary)
            try output.write(toFile: CommandLine.arguments[1] + "/" + name + ".txt", atomically: true, encoding: .utf8)
            var durations: [Double] = []
            for _ in 0..<5 {
                let start = ProcessInfo.processInfo.systemUptime
                let actual = TranscriptionVocabulary.correcting(input, terms: vocabulary)
                precondition(actual == output)
                durations.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
            print("\(name): bytes=\(input.utf8.count), median_ms=\(durations.sorted()[2])")
        }
    }
}
