import Foundation

extension Notification.Name {
    static let transcriptionVocabularyDidChange = Notification.Name("transcriptionVocabularyDidChange")
}

@MainActor
enum TranscriptionVocabulary {
    private static let localKey = "transcription.contextualTerms"
    private static let localUpdatedAtKey = "transcription.contextualTerms.updatedAt"
    private static let cloudRecordKey = "transcription.contextualTerms.record"
    private static let defaults = ["Danobat", "Eneko", "Borja", "Gorosabel", "Ion Azpeitia", "Iván Olariaga"]

    /// App Group storage so the Share extension sees the same list as the app.
    private static let store = UserDefaults(suiteName: "group.com.josumartinez.transcriber") ?? .standard

    static var terms: [String] {
        get {
            let stored = store.stringArray(forKey: localKey)
                ?? UserDefaults.standard.stringArray(forKey: localKey)  // pre-App-Group installs
                ?? defaults
            return Array(stored.prefix(100))
        }
        set {
            save(clean(newValue))
        }
    }

    /// Saves the edited term list only when the cleaned result differs from what
    /// is stored. Editors call this on every keystroke, so it must not write —
    /// or notify — while the effective list is unchanged (e.g. a trailing
    /// newline the user just typed); otherwise the sync-back deletes their input.
    static func updateIfChanged(_ values: [String]) {
        let cleaned = clean(values)
        guard cleaned != terms else { return }
        save(cleaned)
    }

    /// Records that `variant` should always be replaced by `canonical`, merging
    /// into an existing line for the same canonical spelling when there is one.
    static func addAlias(canonical: String, variant: String) {
        let canonical = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        let variant = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty, !variant.isEmpty else { return }

        var lines = terms
        let canonicalKey = normalize(canonical)
        let variantKey = normalize(variant)
        if let index = lines.firstIndex(where: { normalize(parse(line: $0).canonical) == canonicalKey }) {
            let entry = parse(line: lines[index])
            guard variantKey != canonicalKey,
                  !entry.variants.contains(where: { normalize($0) == variantKey })
            else { return }
            lines[index] = "\(entry.canonical) = \((entry.variants + [variant]).joined(separator: ", "))"
        } else if variantKey == canonicalKey {
            lines.append(canonical)
        } else {
            lines.append("\(canonical) = \(variant)")
        }
        terms = lines
        NotificationCenter.default.post(name: .transcriptionVocabularyDidChange, object: nil)
    }

    static func startSync() {
        VocabularySyncCoordinator.shared.start()
        NSUbiquitousKeyValueStore.default.synchronize()
        reconcileWithCloud()
    }

    /// Canonical spellings only — what speech engines should be biased toward.
    /// Alias lines ("Iñaki = Yankee") contribute just their left-hand side.
    static var canonicalTerms: [String] {
        terms.map { Self.parse(line: $0).canonical }
    }

    /// Applies the canonical spelling of short vocabulary terms after recognition.
    /// Fuzzy replacement is deliberately limited to close, long-word matches;
    /// aliases declared as "Canonical = heard1, heard2" are replaced verbatim.
    static func correcting(_ text: String) -> String {
        correcting(text, terms: terms)
    }

    /// Splits a vocabulary line into its canonical spelling and the misheard
    /// variants the user wants replaced (comma-separated). Accepts either
    /// ":" (what the UI now shows) or "=" (legacy lines already synced to
    /// iCloud, which must keep working).
    nonisolated private static func parse(line: String) -> (canonical: String, variants: [String]) {
        guard let separator = line.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
            return (line.trimmingCharacters(in: .whitespaces), [])
        }
        let canonical = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
        let variants = line[line.index(after: separator)...]
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return (canonical, variants)
    }

    nonisolated static func correcting(_ text: String, terms vocabulary: [String]) -> String {
        guard !text.isEmpty else { return text }
        var corrected = text
        let entries = vocabulary.map(parse(line:)).filter { !$0.canonical.isEmpty }

        // User-declared mishearings first: replace each variant with its canonical
        // spelling, whole-word and case-insensitive.
        for entry in entries {
            for variant in entry.variants {
                let pattern = "(?i)(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: variant))(?![\\p{L}\\p{N}])"
                corrected = corrected.replacingOccurrences(of: pattern, with: entry.canonical, options: .regularExpression)
            }
        }

        let canonicals = entries.map(\.canonical)

        // Canonicalize exact multi-word phrases (fixes casing/diacritic drift).
        for term in canonicals where term.contains(where: { $0.isWhitespace }) {
            let pattern = "(?i)(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: term))(?![\\p{L}\\p{N}])"
            corrected = corrected.replacingOccurrences(of: pattern, with: term, options: .regularExpression)
        }

        let singleTerms = canonicals.compactMap { term -> (term: String, normalized: String)? in
            guard !term.contains(where: { $0.isWhitespace }) else { return nil }
            let normalized = normalize(term)
            return normalized.isEmpty ? nil : (term, normalized)
        }
        guard !singleTerms.isEmpty,
              let expression = try? NSRegularExpression(pattern: wordPattern)
        else { return corrected }

        let matches = expression.matches(in: corrected, range: NSRange(corrected.startIndex..., in: corrected))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: corrected) else { continue }
            let recognized = String(corrected[range])
            let normalizedRecognized = normalize(recognized)
            guard let replacement = bestReplacement(for: normalizedRecognized, from: singleTerms),
                  replacement != recognized
            else { continue }
            corrected.replaceSubrange(range, with: replacement)
        }
        return corrected
    }

    /// Word tokens may contain internal apostrophes/periods/hyphens, but must
    /// not swallow trailing punctuation ("danobat." → token "danobat"), or a
    /// replacement would delete the sentence's period.
    nonisolated private static let wordPattern = #"[\p{L}\p{N}](?:[\p{L}\p{N}]|['’.-](?=[\p{L}\p{N}]))*"#

    struct SuspiciousTerm: Identifiable, Equatable {
        var id: String { word }
        let word: String
        let count: Int
        let suggestion: String?
        /// Why this token was offered; never implies an automatic correction.
        let hint: String
        /// The transcript line (or a window of it) around the first occurrence.
        let snippet: String
        /// The `[mm:ss]` timestamp of the line where the word first appears, so
        /// the user knows where to look. Nil for transcripts without markers.
        let timestamp: String?
    }

    /// Mid-sentence unknown names remain candidates. Lowercase tokens require
    /// an explicit, unambiguous user alias OR a unique, one-edit vocabulary
    /// match corroborated by the transcript (repetition or the canonical term
    /// appearing elsewhere). No dictionary of ordinary words is guessed at.
    nonisolated static func suspiciousTerms(in text: String, terms vocabulary: [String]) -> [SuspiciousTerm] {
        guard let expression = try? NSRegularExpression(pattern: wordPattern) else { return [] }
        let entries = vocabulary.map(parse(line:)).filter { !$0.canonical.isEmpty }
        let canonicals = entries.map { (term: $0.canonical, key: normalize($0.canonical)) }
        let knownKeys = Set(canonicals.map(\.key))
        var aliases: [String: Set<String>] = [:]
        for entry in entries {
            for variant in entry.variants where !variant.contains(where: \.isWhitespace) {
                aliases[normalize(variant), default: []].insert(entry.canonical)
            }
        }

        let source = text as NSString
        typealias Occurrence = (word: String, range: NSRange, capitalized: Bool, sentenceStart: Bool)
        var occurrences: [String: [Occurrence]] = [:]
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let word = source.substring(with: match.range)
            let key = normalize(word)
            guard word.count >= 4, !key.isEmpty else { continue }
            let first = word.first!
            let capitalized = first.isUppercase && !word.dropFirst().contains(where: \.isUppercase)
            // A timestamp closing bracket and line breaks also mark starts.
            var lookback = match.range.location - 1
            var previous: Character?
            while lookback >= 0 {
                let character = Character(source.substring(with: NSRange(location: lookback, length: 1)))
                if character == " " || character == "\t" { lookback -= 1; continue }
                previous = character
                break
            }
            let sentenceStart = previous == nil || ".!?\n]…»\"”".contains(previous!)
            occurrences[key, default: []].append((word, match.range, capitalized, sentenceStart))
        }

        var found: [SuspiciousTerm] = []
        for (key, hits) in occurrences where !knownKeys.contains(key) {
            let aliasTargets = aliases[key] ?? []
            // An ambiguous alias must not be presented as a confident match.
            let alias = aliasTargets.count == 1 ? aliasTargets.first : nil
            let nearest = uniqueCloseVocabularyTerm(for: key, among: canonicals)
            let corroborated = hits.count >= 2 || (nearest.map { occurrences[normalize($0)] != nil } ?? false)
            let midSentenceName = hits.first { $0.capitalized && !$0.sentenceStart }
            let lowercase = hits.first { !$0.capitalized && $0.word.first?.isLowercase == true }
            // Repeated sentence-start words alone prove nothing (e.g. "Today").
            // Only offer one if it is independently supported by a close name
            // already present elsewhere in the transcript.
            let repeatedStartName: Occurrence? = {
                guard hits.count >= 2, let nearest, nearest.first?.isUppercase == true,
                      occurrences[normalize(nearest)] != nil else { return nil }
                return hits.first { $0.capitalized && $0.sentenceStart }
            }()
            guard let first = midSentenceName ?? (alias != nil ? hits.first : nil)
                ?? (lowercase != nil && nearest != nil && corroborated ? lowercase : nil)
                ?? repeatedStartName else { continue }
            let suggestion = alias ?? nearest
            let hint: String
            if alias != nil {
                hint = "Matches a variant you added"
            } else if first.capitalized && !first.sentenceStart {
                hint = "Unrecognized name in the middle of a sentence"
            } else if hits.count >= 2 && (nearest.map { occurrences[normalize($0)] == nil } ?? false) {
                hint = "Repeated spelling close to your vocabulary"
            } else {
                hint = "Close to a vocabulary term also used here"
            }
            found.append(SuspiciousTerm(
                word: first.word, count: hits.count, suggestion: suggestion, hint: hint,
                snippet: snippet(around: first.range, in: source),
                timestamp: timestamp(around: first.range, in: source)
            ))
        }
        return found.sorted { lhs, rhs in
            if (lhs.suggestion != nil) != (rhs.suggestion != nil) { return lhs.suggestion != nil }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.word < rhs.word
        }.prefix(25).map(\.self)
    }

    /// Lowercase suggestions must be uniquely plausible, not merely the
    /// closest of several near-identical vocabulary entries. This stricter
    /// threshold is intentionally independent of automatic correction.
    nonisolated private static func uniqueCloseVocabularyTerm(
        for key: String, among canonicals: [(term: String, key: String)]
    ) -> String? {
        guard key.count >= 7 else { return nil }
        let matches = canonicals.filter { candidate in
            guard candidate.key.count >= 7,
                  abs(candidate.key.count - key.count) <= 1,
                  commonPrefixLength(candidate.key, key) >= 3
                    || commonSuffixLength(candidate.key, key) >= 4
            else { return false }
            return editDistance(candidate.key, key, stoppingAfter: 1) == 1
        }
        return matches.count == 1 ? matches[0].term : nil
    }

    /// The `[mm:ss]` / `[h:mm:ss]` marker at the start of the transcript line
    /// containing `range`, returned as the inner text ("00:19"), or nil when the
    /// line has no timestamp. Lets the Suspicious Words list point the user at
    /// where the word occurs.
    nonisolated private static func timestamp(around range: NSRange, in source: NSString) -> String? {
        var lineStart = range.location
        while lineStart > 0, source.character(at: lineStart - 1) != 0x0A {
            lineStart -= 1
        }
        var lineEnd = range.location + range.length
        while lineEnd < source.length, source.character(at: lineEnd) != 0x0A {
            lineEnd += 1
        }
        let line = source.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let inner = String(line[line.index(after: line.startIndex)..<close])
            .trimmingCharacters(in: .whitespaces)
        // Only accept clock-shaped markers, not arbitrary "[...]" bracketed text.
        guard inner.range(of: #"^\d{1,2}(:\d{2}){1,2}$"#, options: .regularExpression) != nil else { return nil }
        return inner
    }

    /// A readable window of text around `range` — the enclosing transcript line
    /// (minus any leading `[timestamp]`), trimmed to at most ~120 characters
    /// centered on the word so the user can see the phrase it appeared in.
    nonisolated private static func snippet(around range: NSRange, in source: NSString) -> String {
        // Expand to the surrounding line.
        var lineStart = range.location
        while lineStart > 0,
              source.character(at: lineStart - 1) != 0x0A {  // newline
            lineStart -= 1
        }
        var lineEnd = range.location + range.length
        while lineEnd < source.length,
              source.character(at: lineEnd) != 0x0A {
            lineEnd += 1
        }
        var line = source.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop a leading "[00:19] " timestamp marker for readability.
        if let bracket = line.firstIndex(of: "]"), line.hasPrefix("[") {
            line = String(line[line.index(after: bracket)...]).trimmingCharacters(in: .whitespaces)
        }

        // Keep the snippet readable; if the line is long, window it around the word.
        let maxLength = 240
        guard line.count > maxLength else { return line }
        let word = source.substring(with: range)
        if let wordRange = line.range(of: word) {
            let padding = (maxLength - word.count) / 2
            let lower = line.index(wordRange.lowerBound, offsetBy: -padding, limitedBy: line.startIndex) ?? line.startIndex
            let upper = line.index(wordRange.upperBound, offsetBy: padding, limitedBy: line.endIndex) ?? line.endIndex
            var windowed = String(line[lower..<upper])
            if lower != line.startIndex { windowed = "…" + windowed }
            if upper != line.endIndex { windowed += "…" }
            return windowed
        }
        return String(line.prefix(maxLength)) + "…"
    }

    fileprivate static func reconcileWithCloud() {
        let cloud = NSUbiquitousKeyValueStore.default
        guard let record = cloud.dictionary(forKey: cloudRecordKey),
              let cloudTerms = record["terms"] as? [String]
        else {
            saveToCloud(terms, updatedAt: Date().timeIntervalSince1970)
            return
        }

        let cloudUpdatedAt = record["updatedAt"] as? Double ?? 0
        let localUpdatedAt = store.double(forKey: localUpdatedAtKey)
        if cloudUpdatedAt >= localUpdatedAt {
            let cleaned = clean(cloudTerms)
            saveLocally(cleaned, updatedAt: cloudUpdatedAt)
            NotificationCenter.default.post(name: .transcriptionVocabularyDidChange, object: nil)
        } else {
            saveToCloud(terms, updatedAt: localUpdatedAt)
        }
    }

    private static func clean(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = normalize(term)
            guard !term.isEmpty, !seen.contains(identity) else { return nil }
            seen.insert(identity)
            return term
        }.prefix(100).map(\.self)
    }

    private static func save(_ cleaned: [String]) {
        let updatedAt = Date().timeIntervalSince1970
        saveLocally(cleaned, updatedAt: updatedAt)
        saveToCloud(cleaned, updatedAt: updatedAt)
    }

    private static func saveLocally(_ values: [String], updatedAt: Double) {
        store.set(values, forKey: localKey)
        store.set(updatedAt, forKey: localUpdatedAtKey)
    }

    private static func saveToCloud(_ values: [String], updatedAt: Double) {
        NSUbiquitousKeyValueStore.default.set(
            ["terms": values, "updatedAt": updatedAt],
            forKey: cloudRecordKey
        )
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }

    nonisolated private static func bestReplacement(
        for recognized: String,
        from candidates: [(term: String, normalized: String)]
    ) -> String? {
        if let exact = candidates.first(where: { $0.normalized == recognized }) {
            return exact.term
        }

        var best: (term: String, distance: Int)?
        for candidate in candidates {
            let limit = candidate.normalized.count >= 8 ? 2 : 1
            guard candidate.normalized.count >= 5,
                  abs(candidate.normalized.count - recognized.count) <= limit,
                  commonPrefixLength(candidate.normalized, recognized) >= 2
                    || commonSuffixLength(candidate.normalized, recognized) >= max(3, candidate.normalized.count / 2)
            else { continue }

            let distance = editDistance(candidate.normalized, recognized, stoppingAfter: limit)
            guard distance <= limit, distance < best?.distance ?? .max else { continue }
            best = (candidate.term, distance)
        }
        return best?.term
    }

    nonisolated private static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix(while: ==).count
    }

    nonisolated private static func commonSuffixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs.reversed(), rhs.reversed()).prefix(while: ==).count
    }

    nonisolated private static func editDistance(_ lhs: String, _ rhs: String, stoppingAfter limit: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            var rowMinimum = current[0]
            for (rightIndex, rightCharacter) in right.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                let value = min(insertion, deletion, substitution)
                current.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            previous = current
        }
        return previous[right.count]
    }
}

@MainActor
private final class VocabularySyncCoordinator {
    static let shared = VocabularySyncCoordinator()
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { _ in
            Task { @MainActor in
                TranscriptionVocabulary.reconcileWithCloud()
            }
        }
    }
}
