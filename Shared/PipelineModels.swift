//
//  PipelineModels.swift
//  Transcriber (Shared between app and Share extension)
//
//  Codable mirrors of the JSON served by actas-server (~/actas-server).
//  These intentionally match the server's pipeline.py output 1:1 so the app
//  can render the pipeline state the Mac already produces.
//

import Foundation

/// A single file in one of the pipeline queues (Inbox, Transcripciones, …).
nonisolated struct PipelineFile: Codable, Hashable, Sendable, Identifiable {
    let name: String
    let path: String
    let size: Int
    let modified: String   // ISO-8601 string from the server

    var id: String { path }

    /// Base name without the audio/text extension — equals the Apple Notes title.
    var baseName: String {
        (name as NSString).deletingPathExtension
    }

    var modifiedDate: Date? {
        ISO8601DateFormatter.actas.date(from: modified)
    }
}

/// launchd agent state as parsed from `launchctl print`.
nonisolated struct LaunchdState: Codable, Hashable, Sendable {
    let label: String
    let loaded: Bool
    let state: String
    let lastExitCode: String?
    let error: String?

    /// Green when loaded and not erroring. Exit 78 (EX_CONFIG) means FDA pending —
    /// surfaced as a distinct "needs attention" rather than a hard failure.
    var isHealthy: Bool {
        loaded && (lastExitCode == nil || lastExitCode == "0" || lastExitCode == "(never exited)")
    }

    var needsFullDiskAccess: Bool {
        (lastExitCode ?? "").hasPrefix("78")
    }
}

/// /tmp lock state for a pipeline stage — `held && alive` means it's running now.
nonisolated struct LockState: Codable, Hashable, Sendable {
    let held: Bool
    let pid: String?
    let alive: Bool

    var isRunning: Bool { held && alive }
}

nonisolated struct PipelineQueues: Codable, Hashable, Sendable {
    let inbox: [PipelineFile]
    let transcriptions: [PipelineFile]
    let processedAudio: [PipelineFile]
    let processedText: [PipelineFile]
    let audioErrors: [PipelineFile]
    let textErrors: [PipelineFile]
    let commands: [PipelineFile]
}

nonisolated struct PipelineLaunchd: Codable, Hashable, Sendable {
    let transcriber: LaunchdState
    let writer: LaunchdState
    let control: LaunchdState
}

nonisolated struct PipelineLocks: Codable, Hashable, Sendable {
    let transcriber: LockState
    let writer: LockState
    let control: LockState
}

nonisolated struct PipelineLogs: Codable, Hashable, Sendable {
    let watchInbox: [String]
    let whisper: [String]
    let watchTranscriptions: [String]
    let writer: [String]
    let control: [String]
}

/// Full /api/status payload.
nonisolated struct PipelineStatus: Codable, Hashable, Sendable {
    let generatedAt: String
    let basePath: String
    let queues: PipelineQueues
    let launchd: PipelineLaunchd
    let locks: PipelineLocks
    let logs: PipelineLogs?
}

/// /api/transcriptions list payload.
nonisolated struct TranscriptionList: Codable, Sendable {
    let processing: [PipelineFile]
    let done: [PipelineFile]
}

/// /api/transcriptions/{name} payload.
nonisolated struct TranscriptionDetail: Codable, Sendable {
    let name: String
    let stage: String      // "processing" | "done"
    let text: String
    let size: Int?
    let modified: String?
}

/// /api/upload result.
nonisolated struct UploadResult: Codable, Sendable {
    struct Queued: Codable, Sendable {
        let name: String
        let path: String
        let size: Int?
    }
    let ok: Bool
    let queued: Queued
}

/// /api/health payload.
nonisolated struct ServerHealth: Codable, Sendable {
    let ok: Bool
    let service: String
    let version: String
    let basePath: String
    let tokenConfigured: Bool
    let fsAccessible: Bool?   // false => server can't read ~/Reuniones (FDA pending)
}

extension ISO8601DateFormatter {
    /// Shared formatter; the server emits fractional seconds + offset.
    /// ISO8601DateFormatter is thread-safe for parsing once configured.
    nonisolated(unsafe) static let actas: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
