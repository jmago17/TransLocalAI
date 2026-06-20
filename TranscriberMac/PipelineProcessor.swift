//
//  PipelineProcessor.swift
//  TranscriberMac
//
//  The engine of the Mac companion. Watches CloudKit-synced PipelineJob records,
//  claims queued ones (transport == .cloudkit), and runs each through
//  transcription → redaction → Apple Notes, updating the job's stage so the iOS
//  app sees progress. Polls on a timer (robust without push setup) plus on launch.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class PipelineProcessor {
    private(set) var isRunning = false
    private(set) var currentJobName: String?
    private(set) var currentStageLabel: String?
    private(set) var lastError: String?
    var doneToday: Int = 0

    private var context: ModelContext?
    private var timer: Timer?
    private let staleClaim: TimeInterval = 15 * 60  // reclaim jobs stuck this long

    func start(context: ModelContext) {
        self.context = context
        tick()
        // Poll every 20s; CloudKit syncs records in the background between ticks.
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// One scheduling pass: if idle, pick the next claimable job and process it.
    func tick() {
        guard !isRunning, let context else { return }
        guard let job = nextClaimable(in: context) else { return }
        Task { await process(job, context: context) }
    }

    // MARK: - Selection

    private func nextClaimable(in context: ModelContext) -> PipelineJob? {
        let all = (try? context.fetch(FetchDescriptor<PipelineJob>(
            sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        // Fresh queued cloudkit jobs first.
        if let q = all.first(where: { $0.transport == .cloudkit && $0.stage == .queued }) {
            return q
        }
        // Reclaim jobs stuck mid-processing (e.g. the app was quit).
        let now = Date()
        return all.first { job in
            job.transport == .cloudkit
            && (job.stage == .transcribing || job.stage == .redacting)
            && now.timeIntervalSince(job.lastSyncedAt ?? .distantPast) > staleClaim
        }
    }

    // MARK: - Processing

    private func process(_ job: PipelineJob, context: ModelContext) async {
        isRunning = true
        lastError = nil
        currentJobName = job.displayName
        defer { isRunning = false; currentJobName = nil; currentStageLabel = nil }

        do {
            // 1) Resolve + download the audio from the iCloud container.
            setStage(job, .transcribing, "Preparando audio", context)
            guard let name = job.audioFileName,
                  let audioURL = AudioFileManager.shared.audioURL(for: name) else {
                throw ProcessError.noAudio
            }
            try await ensureDownloaded(audioURL)

            // 2) Transcribe.
            currentStageLabel = "Transcribiendo"
            let text = try await MacTranscriber.transcribe(audioURL: audioURL)
            saveTranscription(job: job, text: text, context: context)
            setStage(job, .transcribed, "Transcrito", context)

            // 3) Redact the acta and write it to Apple Notes.
            setStage(job, .redacting, "Redactando acta", context)
            let existing = try? NotesWriter.readNote(title: job.displayName)
            let bodyHTML = try await ActaRedactor.redact(
                ActaContext(title: job.displayName, transcription: text, existingNoteBodyHTML: existing),
                using: MacSettings.shared.redact)
            try NotesWriter.writeNote(title: job.displayName, bodyHTML: bodyHTML)

            // 4) Done.
            setStage(job, .done, "Acta lista", context)
            doneToday += 1
        } catch {
            job.errorMessage = error.localizedDescription
            setStage(job, .error, "Error", context)
            lastError = error.localizedDescription
        }
    }

    private func setStage(_ job: PipelineJob, _ stage: PipelineStage, _ label: String, _ context: ModelContext) {
        job.stage = stage
        job.lastSyncedAt = Date()
        currentStageLabel = label
        try? context.save()
    }

    private func saveTranscription(job: PipelineJob, text: String, context: ModelContext) {
        let engineTag: String
        switch MacSettings.shared.transcribe {
        case .appleSpeech: engineTag = "apple"
        case .whisperKit:  engineTag = "whisper"
        case .whisperCpp:  engineTag = "whisper-cpp"
        }
        let t = Transcription(
            timestamp: Date(), title: job.displayName, transcriptionText: text,
            language: "auto", duration: 0, audioFileURL: job.audioFileName, engineUsed: engineTag)
        context.insert(t)
        try? context.save()
    }

    /// Make sure an iCloud ubiquitous item is materialized locally.
    private func ensureDownloaded(_ url: URL) async throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return }
        try? fm.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if fm.fileExists(atPath: url.path) {
                let vals = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if vals?.ubiquitousItemDownloadingStatus == .current || fm.fileExists(atPath: url.path) {
                    return
                }
            }
            try? await Task.sleep(for: .seconds(2))
        }
        throw ProcessError.downloadTimeout
    }

    enum ProcessError: LocalizedError {
        case noAudio, downloadTimeout
        var errorDescription: String? {
            switch self {
            case .noAudio: return "No se encontró el audio del envío."
            case .downloadTimeout: return "El audio no terminó de descargar de iCloud."
            }
        }
    }
}
