import Foundation

/// Manages audio files in the current device's Application Support directory.
final class AudioFileManager: Sendable {
    static let shared = AudioFileManager()

    private let fileManager = FileManager.default
    private let audioDirectoryName = "Audio"

    private init() {}

    // MARK: - Directory Resolution

    private var localAudioDirectory: URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = root.appendingPathComponent(audioDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    var audioDirectory: URL {
        localAudioDirectory
    }

    // MARK: - Save

    /// Saves an audio file locally.
    /// Returns the filename to store in the Transcription model.
    @discardableResult
    func saveAudio(from sourceURL: URL, filename: String) throws -> String {
        let destination = audioDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return filename
    }

    /// Moves an audio file into local app storage.
    /// Use this when the source file is temporary and should not be kept.
    @discardableResult
    func moveAudio(from sourceURL: URL, filename: String) throws -> String {
        let destination = audioDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: sourceURL, to: destination)
        return filename
    }

    // MARK: - Resolve

    /// Returns the local URL for an audio file when it exists.
    func audioURL(for filename: String) -> URL? {
        let localURL = localAudioDirectory.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: localURL.path) ? localURL : nil
    }

    // MARK: - Download Status

    /// Whether the audio file is fully downloaded locally.
    func isDownloaded(filename: String) -> Bool {
        audioURL(for: filename) != nil
    }

    /// Kept for callers that previously needed materialization; local files are already ready.
    func startDownloading(filename: String) throws {
        _ = audioURL(for: filename)
    }

    // MARK: - Delete

    func deleteAudio(filename: String) {
        let localURL = localAudioDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: localURL)
    }
}
