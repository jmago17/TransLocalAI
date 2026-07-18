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
        // Word tokens may contain internal apostrophes/periods/hyphens, but must
        // not swallow trailing punctuation ("danobat." → token "danobat"), or the
        // replacement would delete the sentence's period.
        guard !singleTerms.isEmpty,
              let expression = try? NSRegularExpression(pattern: #"[\p{L}\p{N}](?:[\p{L}\p{N}]|['’.-](?=[\p{L}\p{N}]))*"#)
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
