import Foundation

/// Application-wide terminology layer on top of `TranscriptionVocabulary`.
///
/// The user-visible vocabulary (canonical spellings + "Canonical = heard"
/// aliases) stays in `TranscriptionVocabulary` — it is the iCloud-synced
/// source of truth and what the Settings editor shows. This store adds the
/// metadata the engines need to pick a *ranked subset* instead of dumping the
/// whole list into every request: per-term usage/correction counts, a
/// lifecycle state, and a modest built-in vocabulary that only participates
/// in ranking (it is never synced or shown in the editor).
@MainActor
enum TranscriptionTerminology {

    // MARK: - Model

    enum State: String, Codable {
        case observed      // seen, never validated (built-ins start here)
        case suggested     // repeatedly seen, awaiting user confirmation
        case confirmed     // user typed it or fixed a transcript with it
        case trusted       // confirmed + repeated evidence
        case disabled      // user turned it off — never supplied to engines

        var weight: Int {
            switch self {
            case .trusted: return 40
            case .confirmed: return 30
            case .suggested: return 10
            case .observed: return 4
            case .disabled: return 0
            }
        }
    }

    enum Source: String, Codable {
        case user          // typed into Settings
        case correction    // learned from a transcript fix
        case builtIn
    }

    struct Entry: Identifiable {
        var id: String { normalized }
        let canonical: String
        let aliases: [String]
        let normalized: String
        let state: State
        let source: Source
        let usageCount: Int
        let correctionCount: Int
        let firstSeenAt: Date?
        let lastUsedAt: Date?

        /// Ranking score. Correction evidence dominates (a term the user had
        /// to fix is exactly what the recognizer needs help with), then usage,
        /// then recency. Built-ins only surface when there is room left.
        var score: Int {
            var value = state.weight
            value += min(correctionCount, 10) * 6
            value += min(usageCount, 20)
            if let lastUsed = lastUsedAt,
               Date().timeIntervalSince(lastUsed) < 14 * 24 * 3600 {
                value += 8
            }
            if source == .builtIn { value -= 3 }
            return value
        }
    }

    // MARK: - Persistence (stats only; terms live in TranscriptionVocabulary)

    private struct Stats: Codable {
        var state: State = .confirmed
        var usageCount: Int = 0
        var correctionCount: Int = 0
        var firstSeenAt: Date = Date()
        var lastUsedAt: Date?
    }

    private static let statsKey = "transcription.terminologyStats"
    private static let store = UserDefaults(suiteName: "group.com.josumartinez.transcriber") ?? .standard

    private static func loadStats() -> [String: Stats] {
        guard let data = store.data(forKey: statsKey),
              let decoded = try? JSONDecoder().decode([String: Stats].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func saveStats(_ stats: [String: Stats]) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        store.set(data, forKey: statsKey)
    }

    // MARK: - Built-in vocabulary

    /// Modest built-in vocabulary for common technical/meeting domains. These
    /// feed the ranking only — they start as `.observed` (lowest weight) and
    /// are never written into the user's synced list.
    nonisolated static let builtInTerms: [String] = [
        // Networking / IT
        "Active Directory", "VPN", "RDP", "VNC", "SSH", "DNS", "DHCP",
        "firewall", "TeamViewer", "AnyDesk", "SharePoint", "Outlook",
        "Azure", "AWS", "Kubernetes", "Docker", "GitHub", "GitLab", "Jira",
        // Industrial automation
        "SCADA", "PLC", "HMI", "CNC", "OPC UA", "MES", "ERP", "SAP",
        "Siemens", "Fanuc", "Heidenhain", "Beckhoff", "Profinet", "Modbus"
    ]

    // MARK: - Reading entries

    /// All known terms: user vocabulary lines joined with their stats, then
    /// built-ins that aren't shadowed by a user term.
    static var entries: [Entry] {
        let stats = loadStats()
        var seen = Set<String>()
        var result: [Entry] = []

        for line in TranscriptionVocabulary.terms {
            let parsed = parseLine(line)
            let key = normalize(parsed.canonical)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            let termStats = stats[key]
            result.append(Entry(
                canonical: parsed.canonical,
                aliases: parsed.variants,
                normalized: key,
                state: termStats?.state ?? .confirmed,
                source: (termStats?.correctionCount ?? 0) > 0 ? .correction : .user,
                usageCount: termStats?.usageCount ?? 0,
                correctionCount: termStats?.correctionCount ?? 0,
                firstSeenAt: termStats?.firstSeenAt,
                lastUsedAt: termStats?.lastUsedAt
            ))
        }

        for term in builtInTerms {
            let key = normalize(term)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let termStats = stats[key]
            result.append(Entry(
                canonical: term,
                aliases: [],
                normalized: key,
                state: termStats?.state ?? .observed,
                source: .builtIn,
                usageCount: termStats?.usageCount ?? 0,
                correctionCount: termStats?.correctionCount ?? 0,
                firstSeenAt: termStats?.firstSeenAt,
                lastUsedAt: termStats?.lastUsedAt
            ))
        }
        return result
    }

    /// The ranked subset supplied to engines — highest score first, disabled
    /// terms excluded.
    static func rankedTerms(limit: Int) -> [String] {
        rankedEntries(limit: limit).map(\.canonical)
    }

    static func rankedEntries(limit: Int) -> [Entry] {
        entries
            .filter { $0.state != .disabled }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.canonical < rhs.canonical
            }
            .prefix(limit)
            .map(\.self)
    }

    /// Contextual strings for Apple's SpeechAnalyzer. Generous limit — Apple
    /// handles a larger biasing list well — but still ranked so the most
    /// evidenced terms always make the cut.
    static func appleContextualStrings() -> [String] {
        rankedTerms(limit: 60)
    }

    /// Short list for the Whisper initial prompt. Kept small on purpose:
    /// prompt tokens eat decoding context and a long list increases
    /// hallucination and prompt-echo risk.
    static func whisperPromptTerms() -> [String] {
        rankedTerms(limit: 16)
    }

    // MARK: - Learning

    /// Records a user correction ("heard `variant`, should be `canonical`").
    /// Persists the alias in the synced vocabulary and strengthens the term.
    static func recordCorrection(canonical: String, variant: String) {
        TranscriptionVocabulary.addAlias(canonical: canonical, variant: variant)
        let key = normalize(canonical)
        guard !key.isEmpty else { return }
        var stats = loadStats()
        var termStats = stats[key] ?? Stats()
        termStats.correctionCount += 1
        termStats.lastUsedAt = Date()
        // User corrections are strong evidence: confirmed on first fix,
        // trusted once the same term needed fixing repeatedly.
        if termStats.state != .disabled {
            termStats.state = termStats.correctionCount >= 3 ? .trusted : .confirmed
        }
        stats[key] = termStats
        saveStats(stats)
    }

    /// Scans a finished transcript and bumps usage for every known term that
    /// actually appeared — evidence that the term matters for this user.
    static func recordRecognitions(in text: String) {
        guard !text.isEmpty else { return }
        let haystack = " " + normalizeForSearch(text) + " "
        var stats = loadStats()
        var changed = false
        for entry in entries where entry.state != .disabled {
            let needle = normalizeForSearch(entry.canonical)
            guard !needle.isEmpty, haystack.contains(" \(needle) ") else { continue }
            var termStats = stats[entry.normalized] ?? Stats(state: entry.state)
            termStats.usageCount += 1
            termStats.lastUsedAt = Date()
            // Built-ins seen repeatedly graduate to suggested — still light
            // weight, but ahead of the never-seen ones.
            if termStats.state == .observed && termStats.usageCount >= 3 {
                termStats.state = .suggested
            }
            stats[entry.normalized] = termStats
            changed = true
        }
        if changed { saveStats(stats) }
    }

    /// Enables/disables a term without deleting it from the synced list.
    static func setEnabled(_ enabled: Bool, canonical: String) {
        let key = normalize(canonical)
        var stats = loadStats()
        var termStats = stats[key] ?? Stats()
        termStats.state = enabled ? .confirmed : .disabled
        stats[key] = termStats
        saveStats(stats)
    }

    // MARK: - Management (terminology screen)

    /// Adds a user term to the synced vocabulary (no-op if already present).
    static func addTerm(_ canonical: String) {
        let canonical = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalize(canonical)
        guard !key.isEmpty else { return }
        var lines = TranscriptionVocabulary.terms
        guard !lines.contains(where: { normalize(parseLine($0).canonical) == key }) else { return }
        lines.append(canonical)
        TranscriptionVocabulary.terms = lines
        var stats = loadStats()
        if stats[key] == nil { stats[key] = Stats() }
        saveStats(stats)
        NotificationCenter.default.post(name: .transcriptionVocabularyDidChange, object: nil)
    }

    /// Deletes a user term (line + stats). Built-ins can't be removed from the
    /// shipped list, so they are disabled instead.
    static func deleteTerm(canonical: String) {
        let key = normalize(canonical)
        var lines = TranscriptionVocabulary.terms
        let countBefore = lines.count
        lines.removeAll { normalize(parseLine($0).canonical) == key }
        if lines.count != countBefore {
            TranscriptionVocabulary.terms = lines
            var stats = loadStats()
            stats[key] = nil
            saveStats(stats)
            NotificationCenter.default.post(name: .transcriptionVocabularyDidChange, object: nil)
        } else {
            // Not a user line — a built-in. Disable it.
            setEnabled(false, canonical: canonical)
        }
    }

    /// Rewrites a term's canonical spelling and alias list in place,
    /// carrying its stats over to the new spelling.
    static func updateTerm(originalCanonical: String, newCanonical: String, aliases: [String]) {
        let newCanonical = newCanonical.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldKey = normalize(originalCanonical)
        let newKey = normalize(newCanonical)
        guard !newKey.isEmpty else { return }

        let cleanAliases = aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && normalize($0) != newKey }
        let newLine = cleanAliases.isEmpty
            ? newCanonical
            : "\(newCanonical) = \(cleanAliases.joined(separator: ", "))"

        var lines = TranscriptionVocabulary.terms
        if let index = lines.firstIndex(where: { normalize(parseLine($0).canonical) == oldKey }) {
            lines[index] = newLine
        } else {
            lines.append(newLine)  // editing a built-in materializes it as a user term
        }
        TranscriptionVocabulary.terms = lines

        if oldKey != newKey {
            var stats = loadStats()
            stats[newKey] = stats[oldKey] ?? stats[newKey] ?? Stats()
            stats[oldKey] = nil
            saveStats(stats)
        }
        NotificationCenter.default.post(name: .transcriptionVocabularyDidChange, object: nil)
    }

    /// Approves a suggested/observed term (e.g. a built-in worth keeping).
    static func confirmTerm(canonical: String) {
        let key = normalize(canonical)
        var stats = loadStats()
        var termStats = stats[key] ?? Stats()
        termStats.state = .confirmed
        stats[key] = termStats
        saveStats(stats)
    }

    // MARK: - Import / export

    private struct ExportedEntry: Codable {
        var canonical: String
        var aliases: [String]
        var state: String
        var source: String
        var usageCount: Int
        var correctionCount: Int
    }

    /// Full glossary with metadata as pretty-printed JSON.
    static func exportJSON() -> Data? {
        let exported = entries.map { entry in
            ExportedEntry(
                canonical: entry.canonical,
                aliases: entry.aliases,
                state: entry.state.rawValue,
                source: entry.source.rawValue,
                usageCount: entry.usageCount,
                correctionCount: entry.correctionCount
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(exported)
    }

    /// Imports terms from JSON (this app's export format) or plain text
    /// (one term per line, optional "Canonical = alias1, alias2" syntax).
    /// Existing terms are kept; duplicates are skipped. Returns how many new
    /// terms were added.
    @discardableResult
    static func importTerms(from text: String) -> Int {
        var incoming: [(canonical: String, aliases: [String])] = []
        if let data = text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([ExportedEntry].self, from: data) {
            incoming = decoded.map { ($0.canonical, $0.aliases) }
        } else {
            incoming = text
                .components(separatedBy: .newlines)
                .map { parseLine($0) }
                .map { ($0.canonical, $0.variants) }
        }

        var lines = TranscriptionVocabulary.terms
        // Dedupe against everything already known — user terms AND built-ins —
        // so re-importing an export is a no-op.
        var known = Set(entries.map(\.normalized))
        var added = 0
        for term in incoming {
            let canonical = term.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalize(canonical)
            guard !key.isEmpty, !known.contains(key) else { continue }
            known.insert(key)
            lines.append(term.aliases.isEmpty ? canonical : "\(canonical) = \(term.aliases.joined(separator: ", "))")
            added += 1
        }
        guard added > 0 else { return 0 }
        TranscriptionVocabulary.terms = lines
        NotificationCenter.default.post(name: .transcriptionVocabularyDidChange, object: nil)
        return added
    }

    // MARK: - Helpers

    nonisolated private static func parseLine(_ line: String) -> (canonical: String, variants: [String]) {
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

    nonisolated static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }

    /// Lowercased, diacritic-folded, punctuation collapsed to single spaces —
    /// so word-boundary containment checks stay cheap on long transcripts.
    nonisolated private static func normalizeForSearch(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let mapped = folded.map { character -> Character in
            (character.isLetter || character.isNumber) ? character : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }
}
