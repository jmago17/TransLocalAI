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
