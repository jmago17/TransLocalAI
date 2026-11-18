import Foundation
import Testing
@testable import Transcriber

/// C2: once a Whisper model is on disk, resolving it must not need the
/// network, and a failed download must fall back to a complete local copy.
@Suite(.serialized)
struct WhisperOfflineModelTests {
    private let modelId = "openai_whisper-large-v3-v20240930_626MB"

    private final class Counter: @unchecked Sendable {
        var calls = 0
    }

    private func makeSandbox() throws -> (base: URL, defaults: UserDefaults, suite: String) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-offline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let suite = "whisper-offline-tests-\(UUID().uuidString)"
        return (base, try #require(UserDefaults(suiteName: suite)), suite)
    }

    private func tearDown(_ sandbox: (base: URL, defaults: UserDefaults, suite: String)) {
        try? FileManager.default.removeItem(at: sandbox.base)
        sandbox.defaults.removePersistentDomain(forName: sandbox.suite)
    }

    /// Lays out the files WhisperKit needs, optionally leaving one out.
    @discardableResult
    private func makeModel(in base: URL, missing: String? = nil) throws -> URL {
        let folder = base.appendingPathComponent(modelId, isDirectory: true)
        for component in WhisperLocalModels.requiredComponents {
            for file in WhisperLocalModels.requiredFiles {
                let relative = "\(component)/\(file)"
                guard relative != missing else { continue }
                let url = folder.appendingPathComponent(relative)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data([0x01]).write(to: url)
            }
        }
        return folder
    }

    @Test func verifiedModelResolvesWithoutTheNetwork() async throws {
        let sandbox = try makeSandbox()
        defer { tearDown(sandbox) }
        let folder = try makeModel(in: sandbox.base)
        let counter = Counter()

        // First run: online download, which verifies the folder.
        let first = try await WhisperLocalModels.resolve(modelId: modelId, base: sandbox.base, defaults: sandbox.defaults) {
            counter.calls += 1
            return folder
        }
        #expect(first == folder)
        #expect(counter.calls == 1)

        // Later runs: the downloader (network) is never called again.
        let second = try await WhisperLocalModels.resolve(modelId: modelId, base: sandbox.base, defaults: sandbox.defaults) {
            counter.calls += 1
            throw URLError(.notConnectedToInternet)
        }
        #expect(second.path == folder.path)
        #expect(counter.calls == 1)
    }

    @Test func offlineFallsBackToACompleteCopyFromBeforeVerification() async throws {
        let sandbox = try makeSandbox()
        defer { tearDown(sandbox) }
        let folder = try makeModel(in: sandbox.base)

        let resolved = try await WhisperLocalModels.resolve(modelId: modelId, base: sandbox.base, defaults: sandbox.defaults) {
            throw URLError(.notConnectedToInternet)
        }
        #expect(resolved.path == folder.path)
    }

    @Test func offlineWithAPartialDownloadStillFails() async throws {
        let sandbox = try makeSandbox()
        defer { tearDown(sandbox) }
        try makeModel(in: sandbox.base, missing: "TextDecoder.mlmodelc/weights/weight.bin")

        await #expect(throws: URLError.self) {
            _ = try await WhisperLocalModels.resolve(modelId: modelId, base: sandbox.base, defaults: sandbox.defaults) {
                throw URLError(.notConnectedToInternet)
            }
        }
    }

    @Test func damagedVerifiedFolderGoesBackToTheNetwork() async throws {
        let sandbox = try makeSandbox()
        defer { tearDown(sandbox) }
        let folder = try makeModel(in: sandbox.base)
        let counter = Counter()
        _ = try await WhisperLocalModels.resolve(modelId: modelId, base: sandbox.base, defaults: sandbox.defaults) {
            counter.calls += 1
            return folder
        }

        // Files went missing after verification.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("AudioEncoder.mlmodelc/weights/weight.bin"))
        let redownloaded = try makeModel(in: sandbox.base.appendingPathComponent("fresh", isDirectory: true))
        let resolved = try await WhisperLocalModels.resolve(modelId: modelId, base: sandbox.base, defaults: sandbox.defaults) {
            counter.calls += 1
            return redownloaded
        }
        #expect(counter.calls == 2)
        #expect(resolved == redownloaded)

        // And a folder WhisperKit rejected is forgotten, so it is re-fetched.
        WhisperLocalModels.forget(path: redownloaded.path, defaults: sandbox.defaults)
        _ = try await WhisperLocalModels.resolve(modelId: modelId, base: sandbox.base, defaults: sandbox.defaults) {
            counter.calls += 1
            return redownloaded
        }
        #expect(counter.calls == 3)
    }
}
