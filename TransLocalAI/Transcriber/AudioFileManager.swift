import Foundation

/// Manages audio file storage in the iCloud ubiquity container with fallback to local documents.
/// Audio files sync across devices via iCloud Drive and download on demand.
final class AudioFileManager: Sendable {
    static let shared = AudioFileManager()

    private let fileManager = FileManager.default
    private let audioDirectoryName = "Audio"
    private let containerIdentifier = "iCloud.com.josumartinez.transcriber"

    private init() {}

    // MARK: - Directory Resolution

    /// Returns the iCloud ubiquity Audio directory, or nil if iCloud is unavailable.
    var ubiquityAudioDirectory: URL? {
        guard let container = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            return nil
        }
        let dir = container.appendingPathComponent(audioDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Local documents directory as fallback when iCloud is unavailable.
    private var localAudioDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// The primary directory for storing audio — iCloud if available, local otherwise.
    var audioDirectory: URL {
        ubiquityAudioDirectory ?? localAudioDirectory
    }

    // MARK: - Save

    /// Saves an audio file to the iCloud container (or local fallback).
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

    /// Moves an audio file to the iCloud container (or local fallback).
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

    /// Returns the URL for an audio file. Checks iCloud first, then local fallback.
    func audioURL(for filename: String) -> URL? {
        // Check iCloud ubiquity container first
        if let ubiquityDir = ubiquityAudioDirectory {
            let url = ubiquityDir.appendingPathComponent(filename)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        // Fallback to local documents directory (for pre-migration files)
        let localURL = localAudioDirectory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: localURL.path) {
            return localURL
        }
        // File may exist in iCloud but not yet downloaded — return the ubiquity URL
        if let ubiquityDir = ubiquityAudioDirectory {
            return ubiquityDir.appendingPathComponent(filename)
        }
        return nil
    }

    // MARK: - Download Status

    /// Whether the audio file is fully downloaded locally.
    func isDownloaded(filename: String) -> Bool {
        guard let url = audioURL(for: filename) else { return false }
        // Local files are always available
        if url.path.hasPrefix(localAudioDirectory.path) { return true }

        do {
            let resourceValues = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            return resourceValues.ubiquitousItemDownloadingStatus == .current
        } catch {
            return fileManager.fileExists(atPath: url.path)
        }
    }

    /// Triggers on-demand download of an audio file from iCloud.
    func startDownloading(filename: String) throws {
        guard let url = audioURL(for: filename) else { return }
        guard !url.path.hasPrefix(localAudioDirectory.path) else { return }
        try fileManager.startDownloadingUbiquitousItem(at: url)
    }

    // MARK: - Delete

    /// Deletes an audio file from both iCloud and local storage.
    func deleteAudio(filename: String) {
        if let ubiquityDir = ubiquityAudioDirectory {
            let url = ubiquityDir.appendingPathComponent(filename)
            try? fileManager.removeItem(at: url)
        }
        let localURL = localAudioDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: localURL)
    }

    // MARK: - Migration

    /// Migrates existing audio files from local documents to iCloud ubiquity container.
    /// Call this once on app launch when iCloud becomes available.
    func migrateLocalFilesToCloud() {
        guard let ubiquityDir = ubiquityAudioDirectory else { return }
        let localDir = localAudioDirectory

        guard let files = try? fileManager.contentsOfDirectory(atPath: localDir.path) else { return }
        let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "caf", "aac", "mp4"]

        for file in files {
            let ext = (file as NSString).pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { continue }

            let source = localDir.appendingPathComponent(file)
            let dest = ubiquityDir.appendingPathComponent(file)

            guard !fileManager.fileExists(atPath: dest.path) else {
                // Already in iCloud, remove local copy
                try? fileManager.removeItem(at: source)
                continue
            }

            do {
                try fileManager.moveItem(at: source, to: dest)
            } catch {
                // Keep local copy if migration fails
                print("AudioFileManager: failed to migrate \(file): \(error)")
            }
        }
    }
}
