import Foundation
import Testing
@testable import Transcriber

struct MeetingNotesStrategyTests {
    @Test func splitPreservesLongParagraphAndLimit() {
        let transcript = String(repeating: "palabra", count: 600) + "\n" + String(repeating: "z", count: 4_100)
        let parts = MeetingNotesService.split(transcript, limit: 2_200)
        #expect(parts.count > 2)
        #expect(parts.allSatisfy { !$0.isEmpty && $0.count <= 2_200 })
        #expect(parts.joined() == transcript)
    }

    @Test func splitPreservesBoundaryNewlinesAndUnicode() {
        let transcript = "hola\n\n" + String(repeating: "👩🏽‍💻", count: 103) + "\núltimo\n"
        for limit in [1, 2, 5, 20, 100, 2_200] {
            let parts = MeetingNotesService.split(transcript, limit: limit)
            #expect(parts.joined() == transcript)
            #expect(parts.allSatisfy { $0.count <= limit })
        }
        #expect(MeetingNotesService.split("", limit: 10).isEmpty)
    }

    @Test func assemblyPreservesAllPartsAndDistinctTasks() {
        let extracts = (1...80).map { i in
            """
            # Summary
            - Resumen \(i)
            # Key points
            - Dato \(i)
            # Decisions
            - Decisión \(i)
            # Action items
            - [ ] Acción \(i) — Not specified — Not specified
            # Open questions
            - Pregunta \(i)
            """
        }
        let result = MeetingNotesService.assemble(extracts)
        for i in 1...80 {
            #expect(result.contains("- Decisión \(i)\n"))
            #expect(result.contains("- [ ] Acción \(i) — Not specified — Not specified"))
            #expect(result.contains("- Pregunta \(i)\n") || result.hasSuffix("- Pregunta \(i)"))
        }
        #expect(result.components(separatedBy: "# Action items\n").count == 2)
        #expect(result.range(of: "Resumen 1")!.lowerBound < result.range(of: "Resumen 80")!.lowerBound)
    }

    @Test func assemblyDeduplicatesOnlyExactLinesAndDoesNotInventTasks() {
        let result = MeetingNotesService.assemble([
            "# Decisions\n- Aprobado\n# Action items\n- [ ] Llamar — Ana — lunes",
            "# Decisions\n- Aprobado\n- Aprobado provisionalmente\n# Action items\n- [ ] Llamar — Ana — martes"
        ])
        #expect(result.components(separatedBy: "- Aprobado\n").count == 2)
        #expect(result.contains("- Aprobado provisionalmente"))
        #expect(result.contains("- [ ] Llamar — Ana — lunes"))
        #expect(result.contains("- [ ] Llamar — Ana — martes"))
        #expect(MeetingNotesService.assemble(["# Summary\n- Solo se informó"]).contains("# Action items\nNone recorded"))
    }
}

// Pure strategy checks: invalid model content must never reach persistence.
extension MeetingNotesStrategyTests {
    private var emptySections: String {
        "# Summary\nNone recorded\n# Key points\nNone recorded\n# Decisions\nNone recorded\n# Action items\nNone recorded\n# Open questions\nNone recorded"
    }

    @Test func rejectsRawCopyAndMalformedAndOversizedOutput() {
        let source = String(repeating: "Una frase transcrita muy extensa ", count: 12)
        let copy = emptySections.replacingOccurrences(of: "# Key points\nNone recorded", with: "# Key points\n- \(source)")
        #expect(throws: MeetingNotesError.self) { try MeetingNotesService.validate(copy, source: source, part: 1, merging: false) }
        #expect(throws: MeetingNotesError.self) { try MeetingNotesService.validate("# Summary\n- Solo texto", source: source, part: 1, merging: false) }
        #expect(throws: MeetingNotesError.self) { try MeetingNotesService.validate(String(repeating: "x", count: 1_200), source: source, part: 1, merging: true) }
    }

    @Test func unverifiedTasksAndDecisionsOmittedWithoutLosingFacts() throws {
        let source = "Se acordó enviar el informe el martes. Los libros se leen en euskera."
        let draft = emptySections
            .replacingOccurrences(of: "# Key points\nNone recorded", with: "# Key points\n- Los libros se leen en euskera")
            .replacingOccurrences(of: "# Decisions\nNone recorded", with: "# Decisions\n- Comprar diez tablets ⟦cita inventada⟧")
            .replacingOccurrences(of: "# Action items\nNone recorded", with: "# Action items\n- [ ] Comprar tablets — Ana — lunes ⟦cita inventada⟧")
        let result = try MeetingNotesService.validate(draft, source: source, part: 1, merging: false)
        #expect(result.contains("Los libros se leen"))
        #expect(result.contains("# Decisions\nNone recorded"))
        #expect(result.contains("# Action items\nNone recorded"))
    }

    @Test func citedActionSurvivesMergeOnlyIfCopiedFromChild() throws {
        let quote = "Se acordó enviar el informe el martes"
        let action = "- [ ] Enviar el informe — Not specified — martes ⟦\(quote)⟧"
        let child = try MeetingNotesService.validate(emptySections.replacingOccurrences(of: "# Action items\nNone recorded", with: "# Action items\n\(action)"), source: quote, part: 99, merging: false)
        let merged = try MeetingNotesService.validate(child, source: child, part: 1, merging: true)
        #expect(merged.contains(action))
        let invented = child.replacingOccurrences(of: "martes ⟦", with: "lunes ⟦")
        #expect(try MeetingNotesService.validate(invented, source: child, part: 1, merging: true).contains("# Action items\nNone recorded"))
    }

    @Test func lateChunkIncludedInBoundedGroups() {
        let chunks = (1...80).map { "Parte \($0)" }
        var level = chunks
        while level.count > 1 {
            level = stride(from: 0, to: level.count, by: MeetingNotesService.mergeFanout).map { start in
                level[start..<min(start + MeetingNotesService.mergeFanout, level.count)].joined(separator: ",")
            }
        }
        for part in chunks { #expect(level[0].contains(part)) }
        #expect(level[0].hasSuffix("Parte 80"))
    }
}
