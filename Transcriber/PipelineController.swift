//
//  PipelineController.swift
//  Transcriber
//
//  The brain of the "Actas" tab. Talks to actas-server, reconciles the local
//  PipelineJob records against the Mac's live queue state, and owns the submit
//  flow (HTTP primary, iCloud fallback).
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class PipelineController {
    // Live server view
    var status: PipelineStatus?
    var transcriptions: TranscriptionList?
    var reachability: ServerReachability = .unreachable
    var isRefreshing = false
    var lastError: String?
    /// false => server is reachable but can't read ~/Reuniones (Full Disk Access pending).
    var fsAccessible = true

    private let client = ActasServerClient.shared
    private var eventsTask: Task<Void, Never>?

    var isReachable: Bool {
        if case .reachable = reachability { return true }
        return false
    }

    // MARK: - Refresh

    func refresh(logs: Bool = true) async {
        isRefreshing = true
        defer { isRefreshing = false }
        reachability = await client.reachability()
        guard isReachable else {
            status = nil; transcriptions = nil; fsAccessible = true; return
        }
        // Distinguish "can't read Reuniones (FDA)" from a real outage before
        // hitting the FS endpoints (which would 503).
        if let health = await client.health() {
            fsAccessible = health.fsAccessible ?? true
        }
        guard fsAccessible else {
            status = nil; transcriptions = nil
            lastError = nil
            return
        }
        do {
            async let s = client.status(logs: logs)
            async let t = client.transcriptions()
            self.status = try await s
            self.transcriptions = try await t
            self.fsAccessible = true
            self.lastError = nil
        } catch ActasServerError.fsUnavailable {
            // Reachable but Full Disk Access pending on the Mac.
            self.fsAccessible = false
            self.status = nil
            self.transcriptions = nil
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Reconcile every job against the latest server status, persisting changes.
    /// Force a fresh endpoint probe (used by the pairing screen's test button).
    func testReachability() async -> ServerReachability {
        reachability = await client.reachability(forceRefresh: true)
        return reachability
    }

    func reconcile(jobs: [PipelineJob], context: ModelContext) {
        guard let status else { return }
        var changed = false
        for job in jobs where job.stage != .done {
            let derived = Self.deriveStage(for: job.displayName, status: status)
            if derived != .unknown && derived != job.stage {
                job.stage = derived
                job.lastSyncedAt = Date()
                if derived == .error {
                    job.errorMessage = job.errorMessage ?? "El pipeline marcó este audio como error."
                }
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// Map a display name (== audio base name == note title) to a pipeline stage
    /// by looking at which queue currently holds a matching file.
    static func deriveStage(for displayName: String, status: PipelineStatus) -> PipelineStage {
        let q = status.queues
        func has(_ files: [PipelineFile]) -> Bool {
            files.contains { $0.baseName == displayName }
        }
        if has(q.audioErrors) || has(q.textErrors) { return .error }
        if has(q.processedText) { return .done }
        if has(q.transcriptions) {
            return status.locks.writer.isRunning ? .redacting : .transcribed
        }
        if has(q.processedAudio) { return .transcribed }   // audio archived, txt redacted/cleaned
        if has(q.inbox) {
            return status.locks.transcriber.isRunning ? .transcribing : .queued
        }
        return .unknown
    }

    // MARK: - Submit (HTTP primary, iCloud fallback)

    /// Hand an audio file to the Mac. Returns the job (already inserted into the
    /// context) so the caller can show it.
    @discardableResult
    func submit(audioURL: URL,
                displayName: String,
                source: PipelineSource,
                audioFileName: String?,
                context: ModelContext,
                onProgress: (@Sendable (Double) -> Void)? = nil) async -> PipelineJob {
        let job = PipelineJob(displayName: displayName, source: source, audioFileName: audioFileName)
        job.uploadState = .uploading
        context.insert(job)
        try? context.save()

        // 1) Try HTTP.
        if case .reachable = await client.reachability() {
            do {
                _ = try await client.upload(fileURL: audioURL, displayName: displayName, progress: onProgress)
                job.transport = .http
                job.uploadState = .uploaded
                job.stage = .queued
                try? context.save()
                await refresh(logs: false)
                return job
            } catch {
                job.errorMessage = "HTTP falló: \(error.localizedDescription)"
            }
        }

        // 2) Fallback to iCloud Inbox (if the user granted the folder).
        if ICloudInboxBridge.isConfigured {
            do {
                _ = try ICloudInboxBridge.writeAudioToInbox(from: audioURL, displayName: displayName)
                job.transport = .icloud
                job.uploadState = .uploaded
                job.stage = .queued
                job.errorMessage = nil
                try? context.save()
                return job
            } catch {
                job.errorMessage = "iCloud también falló: \(error.localizedDescription)"
            }
        }

        job.uploadState = .failed
        try? context.save()
        return job
    }

    // MARK: - Commands & retries

    func runCommand(_ action: String) async {
        do { try await client.command(action) }
        catch { lastError = error.localizedDescription }
        await refresh(logs: false)
    }

    func retry(file: PipelineFile, kind: String) async {
        do { try await client.retry(kind: kind, file: file.name) }
        catch { lastError = error.localizedDescription }
        await refresh(logs: false)
    }

    // MARK: - Live updates

    /// Subscribe to the SSE counts stream; refresh whenever queues change.
    func startObservingEvents(refreshHandler: @escaping @MainActor () async -> Void) {
        eventsTask?.cancel()
        eventsTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    for try await _ in self.client.events() {
                        await refreshHandler()
                    }
                } catch {
                    // connection dropped; wait then re-subscribe
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopObservingEvents() {
        eventsTask?.cancel()
        eventsTask = nil
    }
}
