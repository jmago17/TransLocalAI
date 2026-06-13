//
//  ICloudInboxBridge.swift
//  Transcriber (Shared between app and Share extension)
//
//  Fallback path when actas-server is unreachable: drop the audio straight into
//  the Mac's iCloud `Reuniones/Inbox` folder (and commands into `Commands/`), so
//  the existing launchd WatchPaths agents pick it up once iCloud syncs.
//
//  Access to that folder lives outside the app sandbox, so the user grants it
//  once via a folder picker; we persist a security-scoped bookmark in the App
//  Group defaults so the Share extension can reuse it.
//

import Foundation

nonisolated enum ICloudBridgeError: LocalizedError {
    case notConfigured
    case staleBookmark
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "No has elegido la carpeta Reuniones en iCloud todavía."
        case .staleBookmark: return "El acceso a la carpeta Reuniones caducó. Vuelve a elegirla."
        case .accessDenied:  return "iOS denegó el acceso a la carpeta Reuniones."
        }
    }
}

nonisolated enum ICloudInboxBridge {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: ActasServerConfig.appGroup) ?? .standard
    }
    private static let bookmarkKey = "actas.reunionesBookmark"

    static var isConfigured: Bool { defaults.data(forKey: bookmarkKey) != nil }

    /// Persist access to the user-picked Reuniones folder as a bookmark.
    /// Call while the picked URL's security scope is active.
    static func storePickedFolder(_ url: URL) throws {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: bookmarkKey)
    }

    static func clear() { defaults.removeObject(forKey: bookmarkKey) }

    /// Resolve the Reuniones root folder URL from the stored bookmark.
    private static func resolveRoot() throws -> URL {
        guard let data = defaults.data(forKey: bookmarkKey) else { throw ICloudBridgeError.notConfigured }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale {
            // Refresh the bookmark opportunistically.
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    defaults.set(fresh, forKey: bookmarkKey)
                }
            }
        }
        return url
    }

    /// Copy an audio file into Reuniones/Inbox. `displayName` (no extension) is
    /// the Inbox filename and therefore the Apple Notes title.
    @discardableResult
    static func writeAudioToInbox(from sourceURL: URL, displayName: String) throws -> URL {
        let root = try resolveRoot()
        guard root.startAccessingSecurityScopedResource() else { throw ICloudBridgeError.accessDenied }
        defer { root.stopAccessingSecurityScopedResource() }

        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let dest = uniqueDestination(in: inbox, base: displayName, ext: ext)

        // Write atomically: copy to a hidden temp sibling, then rename.
        let tmp = inbox.appendingPathComponent(".\(dest.lastPathComponent).uploading")
        try? FileManager.default.removeItem(at: tmp)
        try FileManager.default.copyItem(at: sourceURL, to: tmp)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Drop a command JSON into Reuniones/Commands (mirrors actas-control's channel).
    static func writeCommand(_ action: String) throws {
        let root = try resolveRoot()
        guard root.startAccessingSecurityScopedResource() else { throw ICloudBridgeError.accessDenied }
        defer { root.stopAccessingSecurityScopedResource() }
        let commands = root.appendingPathComponent("Commands", isDirectory: true)
        try FileManager.default.createDirectory(at: commands, withIntermediateDirectories: true)
        let payload = try JSONSerialization.data(withJSONObject: ["action": action, "source": "translocalai-icloud"])
        let dest = commands.appendingPathComponent("app-\(action)-\(UUID().uuidString.prefix(8)).json")
        try payload.write(to: dest)
    }

    private static func uniqueDestination(in dir: URL, base: String, ext: String) -> URL {
        let safeBase = base.replacingOccurrences(of: "/", with: "-")
        var candidate = dir.appendingPathComponent("\(safeBase).\(ext)")
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(safeBase) (\(i)).\(ext)")
            i += 1
        }
        return candidate
    }
}
