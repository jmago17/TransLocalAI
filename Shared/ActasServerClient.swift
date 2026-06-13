//
//  ActasServerClient.swift
//  Transcriber (Shared between app and Share extension)
//
//  Async client for actas-server. Discovers a reachable endpoint by racing
//  /health across the candidate hosts (Tailscale / LAN / mDNS) and caches the
//  winner. All calls carry the bearer token. When nothing is reachable, callers
//  fall back to the iCloud path (see ICloudInboxBridge).
//

import Foundation

nonisolated enum ActasServerError: LocalizedError {
    case notConfigured
    case unreachable
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "El servidor no está configurado. Empareja la app con el Mac."
        case .unreachable:   return "No se puede contactar con el Mac (ni Tailscale ni LAN)."
        case .http(let code, let body): return "El servidor respondió \(code): \(body)"
        case .decoding(let what): return "Respuesta inesperada del servidor (\(what))."
        }
    }
}

/// Result of an endpoint probe — what the app uses to choose HTTP vs iCloud.
nonisolated enum ServerReachability: Sendable, Equatable {
    case reachable(URL)
    case unreachable
}

actor ActasServerClient {
    static let shared = ActasServerClient()

    private var cachedBaseURL: URL?
    private let probeTimeout: TimeInterval = 2.5
    private let requestTimeout: TimeInterval = 20

    private var session: URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = requestTimeout
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }

    // MARK: - Discovery

    /// Returns a base URL that currently answers /health, or nil. Races all
    /// candidates and keeps the fastest; remembers it for next time.
    func resolveBaseURL(forceRefresh: Bool = false) async -> URL? {
        let config = ActasServerStore.load()
        guard config.isConfigured else { return nil }

        if !forceRefresh, let cached = cachedBaseURL, await isAlive(cached) {
            return cached
        }

        var candidates = config.candidateBaseURLs
        // Try the last known-good first by moving it to the front.
        if let last = ActasServerStore.lastGoodBaseURL,
           let idx = candidates.firstIndex(of: last) {
            candidates.remove(at: idx)
            candidates.insert(last, at: 0)
        }

        let winner = await raceHealth(candidates)
        cachedBaseURL = winner
        ActasServerStore.lastGoodBaseURL = winner
        return winner
    }

    func reachability(forceRefresh: Bool = false) async -> ServerReachability {
        if let url = await resolveBaseURL(forceRefresh: forceRefresh) {
            return .reachable(url)
        }
        return .unreachable
    }

    /// Race /health across candidates, return the first that answers 200.
    private func raceHealth(_ candidates: [URL]) async -> URL? {
        await withTaskGroup(of: URL?.self) { group in
            for base in candidates {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    return await self.isAlive(base) ? base : nil
                }
            }
            for await result in group {
                if let url = result {
                    group.cancelAll()
                    return url
                }
            }
            return nil
        }
    }

    private func isAlive(_ base: URL) async -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("api/health"))
        req.timeoutInterval = probeTimeout
        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let health = try? JSONDecoder().decode(ServerHealth.self, from: data)
            return health?.ok == true
        } catch {
            return false
        }
    }

    // MARK: - Authed request plumbing

    private func base() async throws -> URL {
        guard ActasServerStore.load().isConfigured else { throw ActasServerError.notConfigured }
        guard let url = await resolveBaseURL() else { throw ActasServerError.unreachable }
        return url
    }

    private func authed(_ url: URL, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        let token = ActasServerStore.load().token
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ActasServerError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ActasServerError.decoding(String(describing: T.self)) }
    }

    // MARK: - Endpoints

    func status(logs: Bool = true, logLimit: Int = 80) async throws -> PipelineStatus {
        var comps = URLComponents(url: try await base().appendingPathComponent("api/status"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "logs", value: logs ? "true" : "false"),
                            .init(name: "log_limit", value: String(logLimit))]
        return try await send(authed(comps.url!), as: PipelineStatus.self)
    }

    func transcriptions() async throws -> TranscriptionList {
        try await send(authed(try await base().appendingPathComponent("api/transcriptions")),
                       as: TranscriptionList.self)
    }

    func transcription(name: String) async throws -> TranscriptionDetail {
        let url = try await base().appendingPathComponent("api/transcriptions")
            .appendingPathComponent(name)
        return try await send(authed(url), as: TranscriptionDetail.self)
    }

    func command(_ action: String) async throws {
        var req = authed(try await base().appendingPathComponent("api/command"), method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["action": action])
        _ = try await send(req, as: AckResponse.self)
    }

    func retry(kind: String, file: String) async throws {
        let url = try await base().appendingPathComponent("api/retry")
            .appendingPathComponent(kind)
            .appendingPathComponent(file)
        _ = try await send(authed(url, method: "POST"), as: AckResponse.self)
    }

    func logs(stream: String, limit: Int = 200) async throws -> [String] {
        var comps = URLComponents(
            url: try await base().appendingPathComponent("api/logs").appendingPathComponent(stream),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "limit", value: String(limit))]
        return try await send(authed(comps.url!), as: LogResponse.self).lines
    }

    // MARK: - Upload (multipart, streamed from a temp file, with progress)

    /// Upload an audio file to Inbox/. `displayName` (without extension) becomes
    /// the Inbox filename and therefore the Apple Notes title.
    func upload(fileURL: URL,
                displayName: String,
                progress: (@Sendable (Double) -> Void)? = nil) async throws -> UploadResult {
        let base = try await base()
        let boundary = "Boundary-\(UUID().uuidString)"
        let bodyURL = try Multipart.buildBody(
            fileURL: fileURL,
            uploadName: fileURL.lastPathComponent,
            boundary: boundary,
            fields: ["name": displayName]
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var req = authed(base.appendingPathComponent("api/upload"), method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let delegate = UploadProgressDelegate(onProgress: progress)
        let uploadSession = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { uploadSession.finishTasksAndInvalidate() }

        let (data, resp): (Data, URLResponse) = try await withCheckedThrowingContinuation { cont in
            let task = uploadSession.uploadTask(with: req, fromFile: bodyURL) { data, resp, err in
                if let err { cont.resume(throwing: err) }
                else { cont.resume(returning: (data ?? Data(), resp!)) }
            }
            task.resume()
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw ActasServerError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        do { return try JSONDecoder().decode(UploadResult.self, from: data) }
        catch { throw ActasServerError.decoding("UploadResult") }
    }

    // MARK: - SSE events (queue-count changes)

    /// Streams queue-count snapshots as the server emits them. Ends when the
    /// connection drops; callers can re-subscribe.
    nonisolated func events() -> AsyncThrowingStream<[String: Int], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let base = await self.resolveBaseURL() else {
                    continuation.finish(throwing: ActasServerError.unreachable); return
                }
                var req = URLRequest(url: base.appendingPathComponent("api/events"))
                req.setValue("Bearer \(ActasServerStore.load().token)", forHTTPHeaderField: "Authorization")
                req.timeoutInterval = 3600
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        continuation.finish(throwing: ActasServerError.unreachable); return
                    }
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let json = String(line.dropFirst(6))
                            if let d = json.data(using: .utf8),
                               let counts = try? JSONDecoder().decode([String: Int].self, from: d) {
                                continuation.yield(counts)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Small response shapes

private nonisolated struct AckResponse: Decodable { let ok: Bool }
private nonisolated struct LogResponse: Decodable { let stream: String; let lines: [String] }

// MARK: - Multipart body builder (streams file → temp body, no full in-memory copy)

nonisolated enum Multipart {
    static func buildBody(fileURL: URL, uploadName: String, boundary: String,
                          fields: [String: String]) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmp)
        defer { try? handle.close() }

        func write(_ s: String) { handle.write(Data(s.utf8)) }

        for (key, value) in fields {
            write("--\(boundary)\r\n")
            write("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            write("\(value)\r\n")
        }
        write("--\(boundary)\r\n")
        write("Content-Disposition: form-data; name=\"file\"; filename=\"\(uploadName)\"\r\n")
        write("Content-Type: application/octet-stream\r\n\r\n")

        // Stream the audio in chunks so a 500 MB file never lands in memory.
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while case let chunk = input.readData(ofLength: 1 << 20), !chunk.isEmpty {
            handle.write(chunk)
        }
        write("\r\n--\(boundary)--\r\n")
        return tmp
    }
}

/// Forwards URLSession upload progress to an async-friendly callback.
private nonisolated final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: (@Sendable (Double) -> Void)?
    init(onProgress: (@Sendable (Double) -> Void)?) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend total: Int64) {
        guard total > 0 else { return }
        onProgress?(Double(totalBytesSent) / Double(total))
    }
}
