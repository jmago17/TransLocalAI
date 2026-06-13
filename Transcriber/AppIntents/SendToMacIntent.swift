//
//  SendToMacIntent.swift
//  Transcriber
//
//  Shortcut/Siri entry point to push an audio file into the Mac actas pipeline
//  (HTTP to actas-server, iCloud fallback). The name becomes the Apple Notes
//  title, so the Mac creates/updates the acta with that exact title.
//

import AppIntents
import Foundation

// NOTE: Siri / App Intent metadata (title, description, phrases, parameter
// strings) is rejected by App Store validation (ITMS-90626) if it contains the
// brand/device terms App reserves. The user-facing app UI may still use them;
// only this intent-facing copy is sanitised to neutral words (servidor, Notas).
struct SendToMacIntent: AppIntent {
    static var title: LocalizedStringResource = "Enviar audio para el acta"
    static var description = IntentDescription(
        "Envía un audio para transcribirlo y generar el acta en Notas. Si el servidor no responde, lo deja en iCloud.")

    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    @Parameter(title: "Audio", description: "El audio de la reunión")
    var audioFile: IntentFile

    @Parameter(title: "Título del acta",
               description: "Debe coincidir con la nota en Notas (carpeta Actas)")
    var title: String

    static var parameterSummary: some ParameterSummary {
        Summary("Enviar \(\.$audioFile) para el acta \(\.$title)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let ext = (audioFile.filename as NSString?)?.pathExtension ?? "m4a"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("intent-\(UUID().uuidString).\(ext.isEmpty ? "m4a" : ext)")
        try audioFile.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) HTTP to the server.
        do {
            _ = try await ActasServerClient.shared.upload(fileURL: tempURL, displayName: name)
            return .result(value: "«\(name)» está en la cola del servidor.")
        } catch {
            // 2) iCloud fallback.
            if ICloudInboxBridge.isConfigured {
                _ = try ICloudInboxBridge.writeAudioToInbox(from: tempURL, displayName: name)
                return .result(value: "El servidor no respondía; «\(name)» se guardó en iCloud.")
            }
            throw error
        }
    }
}
