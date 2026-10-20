import Foundation
import Testing
@testable import Transcriber

struct AudioFileManagerTests {
    @Test func localCopyMoveResolveAndDeletePreserveBytes() throws {
        let manager = AudioFileManager.shared
        let filename = "storage-regression-\(UUID().uuidString).wav"
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = Data([0, 1, 2, 3])
        let second = Data([4, 5, 6])
        defer {
            manager.deleteAudio(filename: filename)
            try? FileManager.default.removeItem(at: source)
        }
        #expect(manager.audioURL(for: filename) == nil)
        try first.write(to: source)
        #expect(try manager.saveAudio(from: source, filename: filename) == filename)
        let stored = try #require(manager.audioURL(for: filename))
        #expect(stored == manager.audioDirectory.appendingPathComponent(filename))
        #expect(try Data(contentsOf: stored) == first)
        #expect(FileManager.default.fileExists(atPath: source.path))
        try second.write(to: source)
        #expect(try manager.moveAudio(from: source, filename: filename) == filename)
        #expect(try Data(contentsOf: stored) == second)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        manager.deleteAudio(filename: filename)
        #expect(manager.audioURL(for: filename) == nil)
        manager.deleteAudio(filename: filename)
    }
}
