import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum MeetingNotesError: LocalizedError {
    case unavailable(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .emptyTranscript: "The transcript is empty."
        }
    }
}

enum MeetingNotesService {
    nonisolated static let privateCloudComputePreferenceKey = "meetingNotes.privateCloudComputeEnabled"

    nonisolated static var prefersPrivateCloudCompute: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: privateCloudComputePreferenceKey) != nil else { return true }
        return defaults.bool(forKey: privateCloudComputePreferenceKey)
    }

    nonisolated static var willUsePrivateCloudCompute: Bool {
        guard prefersPrivateCloudCompute else { return false }
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
        instructions: String = shortcutPrompt
    ) async throws -> String {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw MeetingNotesError.emptyTranscript }
        #if canImport(FoundationModels)
        #if compiler(>=6.4)
        if #available(iOS 27, macOS 27, *), prefersPrivateCloudCompute {
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

        return try await generateOnDevice(from: clean, title: title, instructions: instructions)
        #else
        throw MeetingNotesError.unavailable("The language model is not available on this device.")
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26, macOS 26, *)
    private static func generateOnDevice(
        from transcript: String,
        title: String?,
        instructions: String
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

        let chunks = split(transcript, limit: 6_000)
        var extracts: [String] = []
        for (index, chunk) in chunks.enumerated() {
            let session = LanguageModelSession()
            let context = title.map { "Meeting title: \($0)\n" } ?? ""
            let prompt = """
            \(instructions)
            \(context)This is part \(index + 1) of \(chunks.count). Treat timestamps and speaker labels as source text.

            TRANSCRIPT:
            \(chunk)
            """
            extracts.append(try await session.respond(to: prompt).content)
        }
        guard extracts.count > 1 else { return extracts[0] }
        let mergeSession = LanguageModelSession()
        return try await mergeSession.respond(to: """
            Merge the partial meeting notes below into one concise, deduplicated document. Keep the same five Markdown headings. Use only information present in the partial notes. Preserve exact names and retain disagreements or uncertainty.

            \(extracts.joined(separator: "\n\n--- PART ---\n\n"))
            """).content
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

    private static func split(_ text: String, limit: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n") {
            if current.count + paragraph.count + 1 > limit, !current.isEmpty {
                result.append(current)
                current = ""
            }
            if paragraph.count > limit {
                var start = paragraph.startIndex
                while start < paragraph.endIndex {
                    let end = paragraph.index(start, offsetBy: limit, limitedBy: paragraph.endIndex) ?? paragraph.endIndex
                    if !current.isEmpty { result.append(current); current = "" }
                    result.append(String(paragraph[start..<end]))
                    start = end
                }
            } else {
                current += current.isEmpty ? paragraph : "\n\(paragraph)"
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
