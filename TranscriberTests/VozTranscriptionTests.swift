import Foundation
import Testing
@testable import Transcriber

@MainActor
struct VozTranscriptionTests {
    private final class FakeEngine: ModelPreparingTranscriptionEngine {
        var prepared: [String] = []
        var transcribed: [String] = []
        var detections = 0
        var failsUnsupported = false
        let kind: TranscriptionResult.EngineKind
        init(_ kind: TranscriptionResult.EngineKind) { self.kind = kind }
        func detectLanguage(audioURL: URL) async throws -> String {
            detections += 1
            return "es"
        }
        func prepareModel(for language: String, progress: (@Sendable (Double) -> Void)?) async throws {
            prepared.append(language)
            progress?(0.25)
            progress?(1)
        }
        func transcribe(audioURL: URL, language: String, progress: (@Sendable (Double) -> Void)?) async throws -> TranscriptionResult {
            transcribed.append(language)
            if failsUnsupported { throw TranscriptionEngineError.unsupportedLanguage(language) }
            progress?(0.5)
            progress?(1)
            // Empty text avoids touching the persistent terminology feedback store.
            return .init(text: "", language: language, duration: 12.5, engineUsed: kind)
        }
    }
    private nonisolated final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Double] = []
        func append(_ value: Double) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
        var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
    }
    private let url = URL(fileURLWithPath: "/unused-test-audio.wav")

    @Test func explicitSupportedVozRoutesPreparationAndProgress() async throws {
        let apple = FakeEngine(.appleSpeech), whisper = FakeEngine(.whisper), voz = FakeEngine(.voz)
        let service = HybridTranscriptionService(appleEngine: apple, whisperEngine: whisper, vozEngine: voz)
        let preparation = ProgressLog(), transcription = ProgressLog()
        try await service.prepareModelIfNeeded(language: "es-ES", engine: .voz, progress: { preparation.append($0) })
        let result = try await service.transcribe(audioURL: url, language: "es-ES", engine: .voz, progress: { transcription.append($0) })
        #expect(voz.prepared == ["es-ES"])
        #expect(voz.transcribed == ["es-ES"])
        #expect(apple.transcribed.isEmpty && whisper.transcribed.isEmpty)
        #expect(voz.detections == 0)
        #expect(result.engineUsed == .voz && result.duration == 12.5)
        #expect(result.engineUsed.persistedValue == "voz")
        #expect(preparation.values == [0.25, 1])
        #expect(transcription.values == [0.5, 1])
    }

    @Test(arguments: ["eu", "eu-ES", "EU_es", "multilingual"])
    func basqueAndMultilingualNeverPrepareOrRunVoz(_ language: String) async throws {
        let apple = FakeEngine(.appleSpeech), whisper = FakeEngine(.whisper), voz = FakeEngine(.voz)
        let service = HybridTranscriptionService(appleEngine: apple, whisperEngine: whisper, vozEngine: voz)
        #expect(service.engineKind(for: language, engine: .voz) == .whisper)
        try await service.prepareModelIfNeeded(language: language, engine: .voz, progress: nil)
        let result = try await service.transcribe(audioURL: url, language: language, engine: .voz)
        #expect(result.engineUsed == .whisper)
        #expect(whisper.prepared.count == 1 && whisper.transcribed.count == 1)
        #expect(voz.prepared.isEmpty && voz.transcribed.isEmpty)
    }

    @Test(arguments: ["auto", "", "ca-ES", "gl_ES", "zh-Hans", "ja", "unknown"])
    func unsupportedFailsBeforePreparationAndInference(_ language: String) async {
        let apple = FakeEngine(.appleSpeech), whisper = FakeEngine(.whisper), voz = FakeEngine(.voz)
        let service = HybridTranscriptionService(appleEngine: apple, whisperEngine: whisper, vozEngine: voz)
        do {
            try await service.prepareModelIfNeeded(language: language, engine: .voz, progress: nil)
            Issue.record("Unsupported language prepared")
        } catch TranscriptionEngineError.unsupportedLanguage {} catch { Issue.record("Unexpected: \(error)") }
        do {
            _ = try await service.transcribe(audioURL: url, language: language, engine: .voz)
            Issue.record("Unsupported language transcribed")
        } catch TranscriptionEngineError.unsupportedLanguage {} catch { Issue.record("Unexpected: \(error)") }
        #expect(voz.prepared.isEmpty && voz.transcribed.isEmpty)
        #expect(apple.transcribed.isEmpty && whisper.transcribed.isEmpty)
    }

    @Test func automaticRoutingAndFallbackRemainUnchanged() async throws {
        let apple = FakeEngine(.appleSpeech), whisper = FakeEngine(.whisper), voz = FakeEngine(.voz)
        let service = HybridTranscriptionService(appleEngine: apple, whisperEngine: whisper, vozEngine: voz)
        #expect(try await service.transcribe(audioURL: url, language: "es").engineUsed == .appleSpeech)
        #expect(try await service.transcribe(audioURL: url, language: "eu").engineUsed == .whisper)
        #expect(try await service.transcribe(audioURL: url, language: "multilingual").engineUsed == .whisper)
        apple.failsUnsupported = true
        #expect(try await service.transcribe(audioURL: url, language: "ca").engineUsed == .whisper)
        #expect(voz.prepared.isEmpty && voz.transcribed.isEmpty)
        // Old two-engine initializer remains source-compatible and creates no SDK model.
        _ = HybridTranscriptionService(appleEngine: apple, whisperEngine: whisper)
    }

    @Test func explicitVozFailureDoesNotFallBack() async {
        let apple = FakeEngine(.appleSpeech), whisper = FakeEngine(.whisper), voz = FakeEngine(.voz)
        voz.failsUnsupported = true
        let service = HybridTranscriptionService(appleEngine: apple, whisperEngine: whisper, vozEngine: voz)
        do {
            _ = try await service.transcribe(audioURL: url, language: "es", engine: .voz)
            Issue.record("Expected Voz failure")
        } catch TranscriptionEngineError.unsupportedLanguage {} catch { Issue.record("Unexpected: \(error)") }
        #expect(voz.transcribed == ["es-ES"])
        #expect(apple.transcribed.isEmpty && whisper.transcribed.isEmpty)
    }

    @Test func languageNormalizationAndOldSettings() {
        for language in ["es", "es-ES", "ES_es", "pt-BR", "en_US", "uk-UA", " zh-Hans "] {
            #expect(VozLanguagePolicy.supports(language) == !language.contains("zh"))
        }
        #expect(VozLanguagePolicy.supported.count == 25)
        #expect(EnginePreference(rawValue: "Auto") == .auto)
        #expect(EnginePreference(rawValue: "Apple") == .apple)
        #expect(EnginePreference(rawValue: "WhisperKit") == .whisper)
        #expect(TranscriptionResult.EngineKind.appleSpeech.persistedValue == "apple")
        #expect(TranscriptionResult.EngineKind.whisper.persistedValue == "whisper")
    }

    @Test func timestampsPreservePunctuationAndBreakAtPauses() {
        let text = VozTranscriptFormatter.format(words: [
            .init(text: "Hola", start: 5.2, end: 5.5),
            .init(text: ",", start: 5.5, end: 5.6),
            .init(text: "mundo.", start: 5.6, end: 6),
            .init(text: "¿", start: 65, end: 65.1),
            .init(text: "Qué", start: 65.1, end: 65.5),
            .init(text: "tal?", start: 65.5, end: 66),
            .init(text: "Otra", start: 3605, end: 3605.5),
            .init(text: "pausa", start: 3609, end: 3610)
        ], fallback: "unused")
        #expect(text == "[00:05] Hola, mundo.\n[01:05] ¿Qué tal?\n[1:00:05] Otra\n[1:00:09] pausa")
        let blocks = TranscriptPlayerView.parseBlocks(from: text)
        #expect(blocks.map(\.time) == [5, 65, 3605, 3609])
        #expect(VozTranscriptFormatter.format(words: [], fallback: " Hello. ") == "[00:00] Hello.")
        #expect(VozTranscriptFormatter.format(words: [], fallback: " ").isEmpty)
    }

    @Test func cancelledPreparationDoesNotDownload() async {
        let engine = VozTranscriptionEngine()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await engine.prepareModel(for: "es", progress: nil)
        }
        do { try await task.value; Issue.record("Cancellation was ignored") }
        catch is CancellationError {} catch { Issue.record("Unexpected: \(error)") }
    }
}
