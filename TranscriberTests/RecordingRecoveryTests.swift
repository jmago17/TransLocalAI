import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Transcriber

/// I2: recordings that never reached the library (app killed, system stop,
/// stop intent cut off) are recovered from their pending mark — and only
/// those, so a deliberately deleted entry is never resurrected.
@MainActor
@Suite(.serialized)
struct RecordingRecoveryTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Transcription.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        return ModelContext(container)
    }

    /// Writes `seconds` of tone with the recorder's own settings.
    private func writeRecording(named name: String, seconds: Double) throws -> URL {
        let url = AudioFileManager.shared.audioDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: AudioRecorderManager.recordingSettings)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            buffer.floatChannelData![0][index] = sin(Float(index) * 0.05) * 0.3
        }
        try file.write(from: buffer)
        return url
    }

    private func cleanUp(_ names: [String]) {
        for name in names {
            PendingRecordings.remove(fileName: name)
            AudioFileManager.shared.deleteAudio(filename: name)
        }
    }

    @Test func pendingRecordingBecomesALibraryEntryOnce() throws {
        let name = "recovery-test-\(UUID().uuidString).caf"
        defer { cleanUp([name]) }
        _ = try writeRecording(named: name, seconds: 2)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        PendingRecordings.add(fileName: name, title: "Weekly sync", startDate: start)

        let context = try makeContext()
        #expect(RecordingRecovery.recover(into: context) >= 1)

        let entries = try context.fetch(FetchDescriptor<Transcription>(
            predicate: #Predicate { $0.audioFileURL == name }
        ))
        #expect(entries.count == 1)
        #expect(entries.first?.title == "Weekly sync")
        #expect(entries.first?.timestamp == start)
        #expect(abs((entries.first?.duration ?? 0) - 2) < 0.1)
        #expect(!PendingRecordings.entries.contains { $0.fileName == name })

        // Running again must not duplicate it.
        RecordingRecovery.recover(into: context)
        let again = try context.fetchCount(FetchDescriptor<Transcription>(
            predicate: #Predicate { $0.audioFileURL == name }
        ))
        #expect(again == 1)
    }

    @Test func alreadySavedRecordingIsNotDuplicated() throws {
        let name = "recovery-test-\(UUID().uuidString).caf"
        defer { cleanUp([name]) }
        _ = try writeRecording(named: name, seconds: 1)
        PendingRecordings.add(fileName: name, title: "Saved", startDate: Date())

        let context = try makeContext()
        context.insert(Transcription(title: "Saved", transcriptionText: "", language: "multilingual",
                                     duration: 1, audioFileURL: name, engineUsed: ""))
        try context.save()

        RecordingRecovery.recover(into: context)
        let count = try context.fetchCount(FetchDescriptor<Transcription>(
            predicate: #Predicate { $0.audioFileURL == name }
        ))
        #expect(count == 1)
        #expect(!PendingRecordings.entries.contains { $0.fileName == name })
    }

    @Test func missingOrEmptyFilesAreDroppedWithoutEntries() throws {
        let missing = "recovery-test-\(UUID().uuidString).caf"
        let empty = "recovery-test-\(UUID().uuidString).caf"
        defer { cleanUp([missing, empty]) }
        _ = try writeRecording(named: empty, seconds: 0.1)
        PendingRecordings.add(fileName: missing, title: "Gone", startDate: Date())
        PendingRecordings.add(fileName: empty, title: "Blip", startDate: Date())

        let context = try makeContext()
        RecordingRecovery.recover(into: context)

        let count = try context.fetchCount(FetchDescriptor<Transcription>(
            predicate: #Predicate { $0.audioFileURL == missing || $0.audioFileURL == empty }
        ))
        #expect(count == 0)
        #expect(!PendingRecordings.entries.contains { $0.fileName == missing || $0.fileName == empty })
        #expect(AudioFileManager.shared.audioURL(for: empty) == nil)
    }

    @Test func unmarkedAudioFilesAreLeftAlone() throws {
        // An audio file whose entry the user deleted (here or on another
        // device) has no pending mark and must not come back.
        let name = "recovery-test-\(UUID().uuidString).caf"
        defer { cleanUp([name]) }
        _ = try writeRecording(named: name, seconds: 1)

        let context = try makeContext()
        RecordingRecovery.recover(into: context)
        let count = try context.fetchCount(FetchDescriptor<Transcription>(
            predicate: #Predicate { $0.audioFileURL == name }
        ))
        #expect(count == 0)
    }
}
