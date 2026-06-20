//
//  NotesWriter.swift
//  TranscriberMac
//
//  Reads and writes notes in the Apple Notes "Actas" folder via AppleScript,
//  mirroring the convention of the original redactar-acta.sh pipeline: the note
//  title equals the audio name. Runs NSAppleScript on the main thread so the
//  Automation (Apple Events) permission is attributed to this app.
//

import Foundation

enum NotesWriterError: LocalizedError {
    case scriptFailed(String)
    var errorDescription: String? {
        switch self { case .scriptFailed(let m): return "Notas: \(m)" }
    }
}

@MainActor
enum NotesWriter {
    static let folder = "Actas"

    /// Returns the existing note body (HTML) for `title`, or nil if no such note.
    static func readNote(title: String) throws -> String? {
        let script = """
        tell application "Notes"
            set acc to default account
            if not (exists folder "\(esc(folder))" of acc) then return "##NONE##"
            set theNotes to notes of folder "\(esc(folder))" of acc whose name is "\(esc(title))"
            if (count of theNotes) is 0 then return "##NONE##"
            return body of item 1 of theNotes
        end tell
        """
        let out = try run(script)
        return out == "##NONE##" ? nil : out
    }

    /// Create or update the note titled `title` in the Actas folder, setting its
    /// body to `bodyHTML`. Creates the folder if needed.
    static func writeNote(title: String, bodyHTML: String) throws {
        let script = """
        tell application "Notes"
            set acc to default account
            if not (exists folder "\(esc(folder))" of acc) then
                make new folder at acc with properties {name:"\(esc(folder))"}
            end if
            set theFolder to folder "\(esc(folder))" of acc
            set theNotes to notes of theFolder whose name is "\(esc(title))"
            if (count of theNotes) is 0 then
                make new note at theFolder with properties {name:"\(esc(title))", body:"\(esc(bodyHTML))"}
            else
                set body of item 1 of theNotes to "\(esc(bodyHTML))"
            end if
            return "##OK##"
        end tell
        """
        _ = try run(script)
    }

    /// Bring Notes to the front showing the note titled `title` (best-effort).
    static func show(title: String) {
        let script = """
        tell application "Notes"
            activate
            set acc to default account
            if (exists folder "\(esc(folder))" of acc) then
                set theNotes to notes of folder "\(esc(folder))" of acc whose name is "\(esc(title))"
                if (count of theNotes) > 0 then show item 1 of theNotes
            end if
        end tell
        """
        _ = try? run(script)
    }

    // MARK: - AppleScript plumbing

    private static func run(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw NotesWriterError.scriptFailed("no se pudo compilar el script")
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let msg = (error[NSAppleScript.errorMessage] as? String) ?? "\(error)"
            throw NotesWriterError.scriptFailed(msg)
        }
        return result.stringValue ?? ""
    }

    /// Escape a Swift string for embedding inside an AppleScript string literal.
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
