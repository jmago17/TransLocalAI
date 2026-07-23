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
    /// variants the user wants replaced (the part after "=", comma-separated).
    nonisolated private static func parse(line: String) -> (canonical: String, variants: [String]) {
        guard let separator = line.firstIndex(of: "=") else {
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
        /// The transcript line (or a window of it) around the first occurrence.
        let snippet: String
    }

    /// Capitalized words used mid-sentence that match neither a vocabulary
    /// spelling nor a known variant — the usual shape of a misheard name.
    /// Words close to a vocabulary term carry it as a suggestion.
    nonisolated static func suspiciousTerms(in text: String, terms vocabulary: [String]) -> [SuspiciousTerm] {
        guard let expression = try? NSRegularExpression(pattern: wordPattern) else { return [] }
        let entries = vocabulary.map(parse(line:)).filter { !$0.canonical.isEmpty }
        let knownKeys = Set(entries.map { normalize($0.canonical) })
            .union(entries.flatMap(\.variants).map(normalize))
        let canonicals = entries.map { (term: $0.canonical, normalized: normalize($0.canonical)) }

        let source = text as NSString
        var found: [String: (display: String, count: Int, snippet: String)] = [:]
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let word = source.substring(with: match.range)
            guard word.count >= 4, let first = word.first, first.isUppercase,
                  !word.dropFirst().contains(where: \.isUppercase)
            else { continue }

            // Skip words in sentence-start position — capitalization proves
            // nothing there. Timestamps ("[00:19] Word") count as starts too.
            var lookback = match.range.location - 1
            var previous: Character?
            while lookback >= 0 {
                let character = Character(source.substring(with: NSRange(location: lookback, length: 1)))
                if character == " " || character == "\t" { lookback -= 1; continue }
                previous = character
                break
            }
            if previous == nil || ".!?\n]…»\"”".contains(previous!) { continue }

            let key = normalize(word)
            guard !key.isEmpty, !knownKeys.contains(key) else { continue }
            if found[key] == nil {
                found[key] = (word, 1, snippet(around: match.range, in: source))
            } else {
                found[key]?.count += 1
            }
        }

        return found.values.map { entry -> SuspiciousTerm in
            let key = normalize(entry.display)
            let limit = key.count >= 8 ? 3 : 2
            let nearest = canonicals
                .map { (term: $0.term, distance: editDistance($0.normalized, key, stoppingAfter: limit)) }
                .filter { $0.distance <= limit }
                .min { $0.distance < $1.distance }
            return SuspiciousTerm(
                word: entry.display,
                count: entry.count,
                suggestion: nearest?.term,
                snippet: entry.snippet
            )
        }
        .sorted { lhs, rhs in
            if (lhs.suggestion != nil) != (rhs.suggestion != nil) { return lhs.suggestion != nil }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.word < rhs.word
        }
        .prefix(25)
        .map(\.self)
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
