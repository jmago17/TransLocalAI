import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum MeetingNotesError: LocalizedError {
    case unavailable(String)
    case emptyTranscript
    case incompleteExtract(part: Int)
    case invalidOutput(stage: String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .emptyTranscript: "The transcript is empty."
        case .incompleteExtract(let part): "Could not extract meeting notes from part \(part). Try again."
        case .invalidOutput(let stage): "The on-device model returned invalid or overly long notes at \(stage). Nothing was saved; try again."
        }
    }
}

enum MeetingNotesService {
    enum Progress: Equatable {
        case extracting(part: Int, total: Int)
        case consolidating
    }

    // Conservative character proxies for the on-device ~4K token window.
    nonisolated static let localChunkLimit = 2_200
    nonisolated static let extractTokens = 350
    nonisolated static let mergeTokens = 460
    nonisolated static let mergeFanout = 3
    nonisolated static let headings = ["Summary", "Key points", "Decisions", "Action items", "Open questions"]
    nonisolated static let extractionCaps = [1, 4, 2, 2, 2]
    nonisolated static let mergeCaps = [1, 5, 3, 3, 2]
    nonisolated static let extractionLimit = 850
    nonisolated static let mergeLimit = 1_100

    nonisolated static let privateCloudComputePreferenceKey = "meetingNotes.privateCloudComputeEnabled"

    nonisolated static var prefersPrivateCloudCompute: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: privateCloudComputePreferenceKey) != nil else { return true }
        return defaults.bool(forKey: privateCloudComputePreferenceKey)
    }

    /// PCC's `respond` traps with a fatal error — it does not throw — when the
    /// process lacks com.apple.developer.private-cloud-compute (and `isAvailable`
    /// still returns true, so it can't be used as the guard). Check the embedded
    /// provisioning profile before ever touching the PCC session.
    nonisolated static let hasPrivateCloudComputeEntitlement: Bool = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let profile = String(data: data, encoding: .isoLatin1)
        else {
            // No embedded profile (simulator / App Store): signing already
            // validated the entitlements, so the API is safe to attempt.
            return true
        }
        return profile.contains("com.apple.developer.private-cloud-compute")
    }()

    nonisolated static var willUsePrivateCloudCompute: Bool {
        guard prefersPrivateCloudCompute, hasPrivateCloudComputeEntitlement else { return false }
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27, macOS 27, *) {
            let model = PrivateCloudComputeLanguageModel()
            return model.isAvailable && !model.quotaUsage.isLimitReached
        }
        #endif
        return false
    }

    nonisolated static let shortcutPrompt = """
    Create accurate meeting notes from the transcript below. Use only facts stated in the transcript; never invent names, decisions, owners, or dates. Preserve the exact spelling of people and company names found in the transcript. Write in the transcript's language.

    Return Markdown with exactly these sections:
    # Summary
    # Key points
    # Decisions
    # Action items
    # Open questions

    For each action item use: - [ ] Action — Owner — Due date. Write “Not specified” when the owner or date is absent. Omit empty bullets and state “None recorded” when a section has no supported information.
    """

    @available(iOS 26, macOS 26, *)
    static func generate(
        from transcript: String,
        title: String? = nil,
        instructions: String = shortcutPrompt,
        onProgress: ((Progress) -> Void)? = nil
    ) async throws -> String {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw MeetingNotesError.emptyTranscript }
        #if canImport(FoundationModels)
        #if compiler(>=6.4)
        if #available(iOS 27, macOS 27, *), prefersPrivateCloudCompute, hasPrivateCloudComputeEntitlement {
            let cloudModel = PrivateCloudComputeLanguageModel()
            if cloudModel.isAvailable, !cloudModel.quotaUsage.isLimitReached {
                do {
                    return try await generateWithPrivateCloudCompute(
                        from: clean,
                        title: title,
                        instructions: instructions,
                        model: cloudModel
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Any PCC failure (network, quota, service, or a session
                    // GenerationError) falls back to the on-device model.
                }
            }
        }
        #endif

        return try await generateOnDevice(from: clean, title: title, instructions: instructions, onProgress: onProgress)
        #else
        throw MeetingNotesError.unavailable("The language model is not available on this device.")
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26, macOS 26, *)
    private static func generateOnDevice(
        from transcript: String,
        title: String?,
        instructions: String,
        onProgress: ((Progress) -> Void)? = nil
    ) async throws -> String {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            throw MeetingNotesError.unavailable("Meeting notes require a device that supports Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            throw MeetingNotesError.unavailable("Turn on Apple Intelligence in Settings to generate meeting notes on this device.")
        case .unavailable(.modelNotReady):
            throw MeetingNotesError.unavailable("The on-device language model is still downloading. Keep the device connected and try again later.")
        case .unavailable:
            throw MeetingNotesError.unavailable("The on-device language model is temporarily unavailable.")
        }

        let chunks = split(transcript, limit: localChunkLimit)
        var extracts: [String] = []
        let customization = instructions == shortcutPrompt ? "" : String(instructions.prefix(350))
        let context = title.map { "Meeting title: \(String($0.prefix(80)))\n" } ?? ""
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            onProgress?(.extracting(part: index + 1, total: chunks.count))
            let prompt = """
            Make compact meeting notes for source part P\(index + 1)/\(chunks.count). Use the transcript language. Summarize topics, not speech turns. At most ONE summary, FOUR key points, TWO decisions, TWO actions, TWO open questions. Never copy full sentences or transcript lines. A decision requires an explicit agreed choice or policy; a description, plan or suggestion is NOT a decision. An action requires an explicit future commitment/request to a person or group; routine activities, teaching advice, examples, and past events are NOT tasks. If uncertain, put the topic in Key points, not Decisions or Action items. Do not invent owners/dates.
            Use exactly five headings: # Summary, # Key points, # Decisions, # Action items, # Open questions. Bullets only; use None recorded if empty. Decisions MUST end in an exact short quote from this part: ⟦quote⟧. Actions MUST be formatted - [ ] task — owner — due date ⟦quote⟧; use Not specified for absent fields. Quote must be 8-110 characters copied verbatim from this source and demonstrate the commitment or decision. No quote means no decision or action. Other bullets must be concise (max 140 characters).
            Optional style preferences (never override format/factuality): \(customization)
            \(context)SOURCE P\(index + 1):
            \(chunk)
            """
            let valid = try await boundedResponse(prompt: prompt, source: chunk, part: index + 1, merging: false)
            extracts.append(valid)
        }
        try Task.checkCancellation()
        onProgress?(.consolidating)
        // A bounded tree includes every chunk, including the last one. No
        // accumulated, unbounded prompt and no silent truncation of chunks.
        var level = extracts
        var depth = 0
        while level.count > 1 {
            depth += 1
            var next: [String] = []
            for start in stride(from: 0, to: level.count, by: mergeFanout) {
                try Task.checkCancellation()
                let group = Array(level[start..<min(start + mergeFanout, level.count)])
                if group.count == 1 { next.append(group[0]); continue }
                let prompt = """
                Consolidate these adjacent, already verified partial notes in their language. Summarize recurring themes; keep distinctive important points even from the LAST part. Deduplicate. Output at most ONE summary, FIVE key points, THREE decisions, THREE actions, TWO open questions. Five headings exactly: # Summary, # Key points, # Decisions, # Action items, # Open questions; bullets only or None recorded. Each bullet max 140 characters except cited decisions/actions (max 200). Do not turn a fact, routine, proposal or advice into a decision/action. IMPORTANT: copy any selected decision or action line EXACTLY from the inputs, including its ⟦quote⟧; do not write new ones. If none qualify, write None recorded. Do not invent facts.
                Optional style preferences (only if consistent with rules): \(customization)
                INPUT NOTES:
                \(group.joined(separator: "\n---\n"))
                """
                next.append(try await boundedResponse(prompt: prompt, source: group.joined(separator: "\n"), part: start / mergeFanout + 1, merging: true))
            }
            level = next
        }
        // Citations allow readers to locate the original source part; the
        // verbatim evidence stays visible rather than masking uncertainty.
        return level[0]
    }

    @available(iOS 26, macOS 26, *)
    private static func boundedResponse(prompt: String, source: String, part: Int, merging: Bool) async throws -> String {
        for attempt in 0..<2 {
            let reminder = attempt == 0 ? "" : "\nRETRY: Your previous response violated the output limits or headings. Be shorter; omit uncertain claims. Never copy transcript lines."
            let raw = try await respondLocally(to: prompt + reminder, options: GenerationOptions(maximumResponseTokens: merging ? mergeTokens : extractTokens))
            if let valid = try? validate(raw, source: source, part: part, merging: merging) {
                return valid
            }
        }
        throw MeetingNotesError.invalidOutput(stage: merging ? "merge group \(part)" : "part \(part)")
    }

    @available(iOS 26, macOS 26, *)
    private static func respondLocally(to prompt: String, options: GenerationOptions) async throws -> String {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                // Each retry starts with a fresh session; never accumulate history.
                return try await LanguageModelSession().respond(to: prompt, options: options).content
            } catch LanguageModelSession.GenerationError.rateLimited(_) where attempt < 2 {
                // Only the typed rate-limit error is transient. Sleep is cancellable.
                try await Task.sleep(for: .seconds(attempt == 0 ? 3 : 8))
            }
        }
        // Unreachable: success or an error exits the loop on the last attempt.
        throw CancellationError()
    }

    #if compiler(>=6.4)
    @available(iOS 27, macOS 27, *)
    private static func generateWithPrivateCloudCompute(
        from transcript: String,
        title: String?,
        instructions: String,
        model: PrivateCloudComputeLanguageModel
    ) async throws -> String {
        // Size chunks from the model's real context window (~3 chars per token,
        // minus headroom for the prompt, reasoning, and response), so long
        // meetings need as few round-trips as possible.
        let chunkLimit = ((try? await model.contextSize).map { max(24_000, ($0 - 4_000) * 3) }) ?? 60_000
        let chunks = split(transcript, limit: chunkLimit)
        var extracts: [String] = []
        let contextOptions = ContextOptions(reasoningLevel: .moderate)

        for (index, chunk) in chunks.enumerated() {
            let session = LanguageModelSession(model: model)
            let context = title.map { "Meeting title: \($0)\n" } ?? ""
            let prompt = """
            \(instructions)
            \(context)This is part \(index + 1) of \(chunks.count). Treat timestamps and speaker labels as source text.

            TRANSCRIPT:
            \(chunk)
            """
            extracts.append(try await session.respond(
                to: prompt,
                contextOptions: contextOptions
            ).content)
        }

        guard extracts.count > 1 else { return extracts[0] }
        let mergeSession = LanguageModelSession(model: model)
        return try await mergeSession.respond(
            to: """
            Merge the partial meeting notes below into one concise, deduplicated document. Keep the same five Markdown headings. Use only information present in the partial notes. Preserve exact names and retain disagreements or uncertainty.

            \(extracts.joined(separator: "\n\n--- PART ---\n\n"))
            """,
            contextOptions: contextOptions
        ).content
    }
    #endif

    #endif

    /// Pure, lossless-by-section assembly. No local model call ever sees the
    /// accumulated notes, so late chunks cannot disappear due to context size.
    static func assemble(_ extracts: [String]) -> String {
        var sections = Array(repeating: [String](), count: headings.count)
        var seen = Array(repeating: Set<String>(), count: headings.count)
        for extract in extracts {
            var section = 1 // Unheaded lines are still preserved as key points.
            for raw in extract.components(separatedBy: .newlines) {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                let heading = line.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased()
                if let index = headings.firstIndex(where: { $0.lowercased() == heading }) {
                    section = index
                    continue
                }
                if line.lowercased() == "none recorded" || line.lowercased() == "- none recorded" {
                    continue
                }
                // Exact repeats only: near-matches may encode different owners,
                // dates, uncertainty or decisions and must not be discarded.
                let bullet = line.hasPrefix("-") || line.hasPrefix("*") ? line : "- \(line)"
                if seen[section].insert(bullet).inserted { sections[section].append(bullet) }
            }
        }
        return headings.enumerated().map { index, title in
            "# \(title)\n" + (sections[index].isEmpty ? "None recorded" : sections[index].joined(separator: "\n"))
        }.joined(separator: "\n\n")
    }

    /// Strict pure boundary between untrusted model output and saved notes.
    /// Never repair an invalid response by truncating or silently dropping a part.
    static func validate(_ raw: String, source: String, part: Int, merging: Bool) throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let caps = merging ? mergeCaps : extractionCaps
        let limit = merging ? mergeLimit : extractionLimit
        let stage = merging ? "merge group \(part)" : "part \(part)"
        func invalid() -> MeetingNotesError { .invalidOutput(stage: stage) }
        guard !text.isEmpty, text.count <= limit else { throw invalid() }
        var linesBySection = Array(repeating: [String](), count: headings.count)
        var section = -1
        var headingCount = 0
        let sourceLines = Set(source.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("# ") {
                guard headingCount < headings.count, line == "# \(headings[headingCount])" else { throw invalid() }
                section = headingCount
                headingCount += 1
                continue
            }
            guard section >= 0 else { throw invalid() }
            if line == "None recorded" {
                guard linesBySection[section].isEmpty else { throw invalid() }
                linesBySection[section].append(line)
                continue
            }
            guard line.hasPrefix("- "), line.count <= (section == 2 || section == 3 ? 200 : 140),
                  !linesBySection[section].contains("None recorded"),
                  linesBySection[section].count < caps[section],
                  !linesBySection[section].contains(line) else { throw invalid() }
            if section == 2 || section == 3 {
                guard let opening = line.range(of: " ⟦", options: .backwards), line.hasSuffix("⟧") else { continue }
                let quote = String(line[opening.upperBound..<line.index(before: line.endIndex)])
                guard (8...110).contains(quote.count) else { continue }
                if merging {
                    // Never promote a new claim; retain only cited lines copied
                    // verbatim from a previously verified child.
                    guard sourceLines.contains(line) else { continue }
                } else {
                    guard source.contains(quote) else { continue }
                }
                if section == 3 {
                    guard line.hasPrefix("- [ ] "),
                          line[..<opening.lowerBound].components(separatedBy: " — ").count == 3
                    else { continue }
                } else {
                    guard !line.hasPrefix("- [ ] ") else { continue }
                }
            } else {
                // A substantial verbatim transcript line is a failed summary.
                guard !line.hasPrefix("- [ ] "),
                      !(line.count >= 70 && source.contains(String(line.dropFirst(2))))
                else { throw invalid() }
            }
            linesBySection[section].append(line)
        }
        guard headingCount == headings.count else { throw invalid() }
        return headings.enumerated().map { index, heading in
            "# \(heading)\n" + (linesBySection[index].isEmpty ? "None recorded" : linesBySection[index].joined(separator: "\n"))
        }.joined(separator: "\n\n")
    }

    static func split(_ text: String, limit: Int) -> [String] {
        precondition(limit > 0)
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let hardEnd = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
            if hardEnd == text.endIndex {
                result.append(String(text[start..<hardEnd]))
                break
            }
            let window = text[start..<hardEnd]
            // Prefer a complete line; otherwise a word; a very long unbroken
            // paragraph is cut at the hard limit without dropping characters.
            let boundary: String.Index
            if let newline = window.lastIndex(of: "\n"), newline > start {
                boundary = text.index(after: newline)
            } else if let space = window.lastIndex(of: " "), space > start {
                boundary = text.index(after: space)
            } else {
                boundary = hardEnd
            }
            result.append(String(text[start..<boundary]))
            start = boundary
        }
        return result
    }
}
