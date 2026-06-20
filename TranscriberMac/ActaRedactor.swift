//
//  ActaRedactor.swift
//  TranscriberMac
//
//  Turns a meeting transcription into the acta body (HTML for Apple Notes),
//  preserving any manual notes the user already wrote in the note. Mirrors the
//  prompt of the original redactar-acta.sh. Pluggable backend: Apple Foundation
//  Models (default, on-device), OpenAI API, or a local CLI (OpenAI / Claude).
//

import Foundation
import FoundationModels

struct ActaContext {
    let title: String
    let transcription: String
    let existingNoteBodyHTML: String?
}

enum ActaRedactorError: LocalizedError {
    case noAPIKey
    case backendFailed(String)
    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "Falta la clave de API (configúrala en Ajustes)."
        case .backendFailed(let m): return "Redacción: \(m)"
        }
    }
}

@MainActor
enum ActaRedactor {
    /// Produce the full note body (HTML) for the acta.
    static func redact(_ ctx: ActaContext, using backend: RedactBackend) async throws -> String {
        let prompt = buildPrompt(ctx)
        switch backend {
        case .appleFoundation: return try await appleFoundation(prompt)
        case .openAI:          return try await openAI(prompt)
        case .openAICLI:       return try await cli(prompt, binary: MacSettings.shared.redactCliPath, args: [])
        case .claudeCLI:       return try await cli(prompt, binary: MacSettings.shared.redactCliPath, args: ["--print"])
        }
    }

    // MARK: - Prompt (Spanish, acta de reunión → HTML)

    private static func buildPrompt(_ ctx: ActaContext) -> String {
        let existing = ctx.existingNoteBodyHTML.map {
            "\n\nLa nota YA EXISTE. Este es su contenido HTML actual (respeta la cabecera y cualquier nota manual del usuario; reescribe solo la sección del acta generada):\n---\n\($0)\n---\n"
        } ?? "\n\nLa nota no existe todavía; produce el cuerpo completo.\n"

        return """
        Eres un redactor de actas de reunión de Danobat. A partir de una transcripción, devuelve el CUERPO COMPLETO de una nota de Apple Notes en HTML simple (usa <h1>, <h2>, <ul>/<li>, <p>, <table> si hace falta; nada de <html>/<head>/<body>, solo el contenido).

        Título de la reunión: \(ctx.title)
        \(existing)
        Estructura del acta (en español formal, en pasado, tercera persona; NO inventes, si falta un dato pon [pendiente confirmar]):
        - Datos de la reunión (proyecto/área, fecha, hora, lugar/modalidad, convocante, redactor: Josu Martínez)
        - Asistentes (internos Danobat, externos, excusados, distribución)
        - Orden del día
        - Desarrollo de la reunión (por tema: contexto, discusión, conclusión)
        - Acuerdos y decisiones
        - Acciones / Plan de trabajo (tabla: ID, acción, responsable, fecha objetivo, estado)
        - Riesgos / Puntos abiertos
        - Próxima reunión
        - Puntos a revisar antes de distribuir

        Nombres habituales Danobat (corrige errores de transcripción): Eneko, Borja, Gorosabel, Ion Azpeitia, Iván Olariaga.

        Si la nota ya existía, conserva la cabecera y las notas manuales del usuario tal cual, y solo regenera la parte del acta. Las notas manuales son información PRIORITARIA: úsalas para corregir o completar la transcripción.

        Devuelve SOLO el HTML del cuerpo, sin explicaciones ni vallas de código.

        TRANSCRIPCIÓN:
        ---
        \(ctx.transcription)
        ---
        """
    }

    // MARK: - Backends

    private static func appleFoundation(_ prompt: String) async throws -> String {
        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: prompt)
            return stripFences(response.content)
        } catch {
            throw ActaRedactorError.backendFailed(error.localizedDescription)
        }
    }

    private static func openAI(_ prompt: String) async throws -> String {
        guard let key = MacSettings.shared.openAIKey(), !key.isEmpty else { throw ActaRedactorError.noAPIKey }
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": MacSettings.shared.openAIModel,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.2,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw ActaRedactorError.backendFailed(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw ActaRedactorError.backendFailed("respuesta inesperada de OpenAI")
        }
        return stripFences(content)
    }

    /// Shell out to a local CLI that takes the prompt on stdin and prints the result.
    private static func cli(_ prompt: String, binary: String, args: [String]) async throws -> String {
        try await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: binary)
            proc.arguments = args
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            proc.standardInput = stdin; proc.standardOutput = stdout; proc.standardError = stderr
            // Ensure Homebrew + user-local bins are on PATH.
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:" +
                NSString(string: "~/.local/bin").expandingTildeInPath
            proc.environment = env
            do { try proc.run() } catch {
                throw ActaRedactorError.backendFailed("no se pudo ejecutar \(binary): \(error.localizedDescription)")
            }
            stdin.fileHandleForWriting.write(Data(prompt.utf8))
            stdin.fileHandleForWriting.closeFile()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw ActaRedactorError.backendFailed("CLI salió \(proc.terminationStatus): \(err)")
            }
            return Self.stripFences(String(data: outData, encoding: .utf8) ?? "")
        }.value
    }

    nonisolated private static func stripFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            // drop the opening fence line and trailing fence
            if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) }
            if let r = t.range(of: "```", options: .backwards) { t = String(t[..<r.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
