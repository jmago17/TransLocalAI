//
//  MeetingNotesProbeTests.swift
//  TranscriberTests
//
//  On-device probes to isolate which FoundationModels API asserts on
//  iOS 27 beta. Run individually with -only-testing; a crashed test runner
//  identifies the faulty call.
//

import Testing
import Foundation
@testable import Transcriber

#if canImport(FoundationModels) && compiler(>=6.4)
import FoundationModels

struct MeetingNotesProbeTests {

    @Test func pccAvailabilityProbe() {
        guard #available(iOS 27, macOS 27, *) else { return }
        let model = PrivateCloudComputeLanguageModel()
        _ = model.isAvailable
        _ = model.quotaUsage.isLimitReached
        #expect(Bool(true))
    }

    @Test func pccContextSizeProbe() async {
        guard #available(iOS 27, macOS 27, *) else { return }
        let model = PrivateCloudComputeLanguageModel()
        let size = try? await model.contextSize
        print("PROBE contextSize:", size ?? -1)
        #expect(Bool(true))
    }

    @Test func pccRespondPlainProbe() async throws {
        guard #available(iOS 27, macOS 27, *) else { return }
        // Without the entitlement, respond traps fatally instead of throwing.
        guard MeetingNotesService.hasPrivateCloudComputeEntitlement else { return }
        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable else { return }
        let session = LanguageModelSession(model: model)
        let response = try await session.respond(to: "Reply with the single word: hello")
        print("PROBE plain respond:", response.content.prefix(80))
    }

    @Test func pccRespondWithContextOptionsProbe() async throws {
        guard #available(iOS 27, macOS 27, *) else { return }
        // Without the entitlement, respond traps fatally instead of throwing.
        guard MeetingNotesService.hasPrivateCloudComputeEntitlement else { return }
        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable else { return }
        let session = LanguageModelSession(model: model)
        let response = try await session.respond(
            to: "Reply with the single word: hello",
            contextOptions: ContextOptions(reasoningLevel: .moderate)
        )
        print("PROBE contextOptions respond:", response.content.prefix(80))
    }

    @Test func onDeviceRespondProbe() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        guard case .available = SystemLanguageModel.default.availability else { return }
        let session = LanguageModelSession()
        let response = try await session.respond(to: "Reply with the single word: hello")
        print("PROBE on-device respond:", response.content.prefix(80))
    }
}
#endif
