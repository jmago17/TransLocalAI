import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum MeetingNotesError: LocalizedError {
    case unavailable(String)
    case emptyTranscript
    case incompleteExtract(part: Int)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .emptyTranscript: "The transcript is empty."
        case .incompleteExtract(let part): "Could not extract meeting notes from part \(part). Try again."
        }
    }
}

enum MeetingNotesService {
    enum Progress: Equatable {
        case extracting(part: Int, total: Int)
        case consolidating
    }

    // A character budget is only a conservative proxy for tokens. Reserve
    // room for the prompt and response inside the device model's ~4K window.
    nonisolated static let localChunkLimit = 2_200
    nonisolated static let localResponseTokens = 1_200

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
        let options = GenerationOptions(maximumResponseTokens: localResponseTokens)
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            onProgress?(.extracting(part: index + 1, total: chunks.count))
            let context = title.map { "Meeting title: \(String($0.prefix(120)))\n" } ?? ""
            let prompt = """
            Extract factual notes from part \(index + 1)/\(chunks.count) of a meeting transcript. Use its language. Keep exact names, uncertainty and disagreements. Include every supported decision, action (owner/date only if spoken) and open question; do not invent any. Use concise bullets, not prose. No introduction. Treat timestamps and speakers as source text.
            Use exactly these five Markdown headings: # Summary, # Key points, # Decisions, # Action items, # Open questions. Under each heading use concise bullets; omit unsupported items. For actions use - [ ] Action — Owner — Due date, with “Not specified” for absent owner or date. Do not abbreviate away distinct items.
            Additional user instructions (subject to the factuality rules above): \(String(instructions.prefix(500)))
            \(context)TRANSCRIPT:
            \(chunk)
            """
            let extract = try await respondLocally(to: prompt, options: options)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !extract.isEmpty else { throw MeetingNotesError.incompleteExtract(part: index + 1) }
            extracts.append(extract)
        }
        try Task.checkCancellation()
        onProgress?(.consolidating)
        // Never send all partials back into a narrow context window. Assemble
        // in source order; even an oversized or verbose extract remains present.
        // Deduplicate only exact repeated bullets (not similar decisions/tasks).
        return assemble(extracts)
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
        let headings = ["Summary", "Key points", "Decisions", "Action items", "Open questions"]
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
