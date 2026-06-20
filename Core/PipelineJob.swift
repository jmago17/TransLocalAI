//
//  PipelineJob.swift
//  Transcriber
//
//  Tracks an audio the app handed to the Mac pipeline, so the user can follow
//  it from "uploading" all the way to "acta en Apple Notes". The server is the
//  source of truth for live stage; this is the app's local memory of *what it
//  sent* so it can correlate against /api/status by name.
//

import Foundation
import SwiftData

enum PipelineSource: String, Codable, Sendable, CaseIterable {
    case recorded, imported, shared
}

enum PipelineTransport: String, Codable, Sendable {
    case http       // uploaded over HTTP to actas-server
    case icloud     // dropped into Reuniones/Inbox via iCloud fallback
}

enum PipelineUploadState: String, Codable, Sendable {
    case pending        // not yet sent
    case uploading
    case uploaded       // reached the Mac (HTTP 2xx or iCloud copy done)
    case failed         // both HTTP and iCloud failed
}

/// Derived from the server's view of the queues. Ordered by progress.
enum PipelineStage: String, Codable, Sendable, CaseIterable {
    case unknown
    case queued         // audio sits in Inbox
    case transcribing   // transcriber lock running on it
    case transcribed    // .txt exists / audio archived to Procesadas
    case redacting      // writer lock running on the .txt
    case done           // acta written, .txt in Procesadas-Txt
    case error          // landed in Errores / Errores-Txt

    var order: Int {
        switch self {
        case .unknown: return 0
        case .queued: return 1
        case .transcribing: return 2
        case .transcribed: return 3
        case .redacting: return 4
        case .done: return 5
        case .error: return -1
        }
    }

    var label: String {
        switch self {
        case .unknown: return "Sin estado"
        case .queued: return "En cola"
        case .transcribing: return "Transcribiendo"
        case .transcribed: return "Transcrito"
        case .redacting: return "Redactando acta"
        case .done: return "Acta lista"
        case .error: return "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .queued: return "tray.and.arrow.down"
        case .transcribing: return "waveform"
        case .transcribed: return "text.alignleft"
        case .redacting: return "doc.text.magnifyingglass"
        case .done: return "checkmark.seal.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

@Model
final class PipelineJob {
    var id: UUID = UUID()
    var displayName: String = ""          // audio base name == Apple Notes title
    var createdAt: Date = Date()
    var audioFileName: String?            // local copy ref (AudioFileManager)
    var lastSyncedAt: Date?
    var errorMessage: String?

    // Stored as raw strings for SwiftData + CloudKit compatibility.
    var sourceRaw: String = PipelineSource.recorded.rawValue
    var transportRaw: String = PipelineTransport.http.rawValue
    var uploadStateRaw: String = PipelineUploadState.pending.rawValue
    var stageRaw: String = PipelineStage.unknown.rawValue

    init(displayName: String,
         source: PipelineSource = .recorded,
         audioFileName: String? = nil) {
        self.id = UUID()
        self.displayName = displayName
        self.createdAt = Date()
        self.audioFileName = audioFileName
        self.sourceRaw = source.rawValue
    }

    var source: PipelineSource {
        get { PipelineSource(rawValue: sourceRaw) ?? .recorded }
        set { sourceRaw = newValue.rawValue }
    }
    var transport: PipelineTransport {
        get { PipelineTransport(rawValue: transportRaw) ?? .http }
        set { transportRaw = newValue.rawValue }
    }
    var uploadState: PipelineUploadState {
        get { PipelineUploadState(rawValue: uploadStateRaw) ?? .pending }
        set { uploadStateRaw = newValue.rawValue }
    }
    var stage: PipelineStage {
        get { PipelineStage(rawValue: stageRaw) ?? .unknown }
        set { stageRaw = newValue.rawValue }
    }

    /// True once the acta is in Apple Notes — terminal success.
    var isComplete: Bool { stage == .done }
}
