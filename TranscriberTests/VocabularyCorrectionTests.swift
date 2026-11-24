import Testing
@testable import Transcriber

struct VocabularyCorrectionTests {
    @Test func preservesUnicodeAndPunctuationAcrossLengthChangingReplacements() {
        let input = "👩🏽‍💻 [00:19] inaki, INAKI; danobat.\n日本語: inaki — café!"
        #expect(TranscriptionVocabulary.correcting(input, terms: ["Iñaki", "Danobat"])
            == "👩🏽‍💻 [00:19] Iñaki, Iñaki; Danobat.\n日本語: Iñaki — café!")
    }

    @Test func preservesDecomposedMarksDuringCorrection() {
        let input = "danobat\u{301} danobat inaki\u{301}"
        #expect(TranscriptionVocabulary.correcting(input, terms: ["Danobat", "Iñaki"])
            == "Danobat\u{301} Danobat Iñaki\u{301}")
    }

    @Test func repeatedMissesAndMatchesPreserveTheirOriginalPositions() {
        let input = String(repeating: "untouched gorosbel, untouched DANOBAT!\n", count: 100)
        let expected = String(repeating: "untouched Gorosabel, untouched Danobat!\n", count: 100)
        #expect(TranscriptionVocabulary.correcting(input, terms: ["Gorosabel", "Danobat"]) == expected)
    }

    @Test func cacheDoesNotSurviveVocabularyChanges() {
        let input = "danobat danobat"
        #expect(TranscriptionVocabulary.correcting(input, terms: ["Danobat"]) == "Danobat Danobat")
        #expect(TranscriptionVocabulary.correcting(input, terms: []) == input)
        #expect(TranscriptionVocabulary.correcting(input, terms: ["DANOBAT"]) == "DANOBAT DANOBAT")
    }

    @Test func preservesOrderedAliasAndPhrasePasses() {
        #expect(TranscriptionVocabulary.correcting(
            "Yankee met ion azpeitia. Yankee!", terms: ["Ianki: Yankee", "Iñaki = Ianki", "Ion Azpeitia"]
        ) == "Iñaki met Ion Azpeitia. Iñaki!")
    }

    @Test func unchangedTokensAndEmptyInputRoundTripExactly() {
        let input = "  👋 日本語\r\nprofessor\tperformance…  "
        #expect(TranscriptionVocabulary.correcting(input, terms: ["Profactor"]) == input)
        #expect(TranscriptionVocabulary.correcting("", terms: ["Danobat"]) == "")
    }

    // Regressions for audit C3 (2026-11-17): folded case/diacritics made
    // capitalized terms swallow ordinary Spanish words.
    @Test func leavesOrdinaryWordsThatFoldOntoShortOrCloseNamesUntouched() {
        let cases: [(String, [String])] = [
            ("No lo borra nadie, en la forja.", ["Borja"]),
            ("Borra eso. Forja el hierro.", ["Borja"]),
            ("Qué pena me da. Pena no es.", ["Peña"]),
            ("Quiero más café. Más tarde.", ["Mas"]),
            ("Salió el sol sobre la rosa.", ["Sol", "Rosa"]),
        ]
        for (input, terms) in cases {
            #expect(TranscriptionVocabulary.correcting(input, terms: terms) == input)
        }
    }

    @Test func stillFixesNamesWhenTheTokenLooksLikeOne() {
        // Exact folded match of a 5+ letter term, even lowercase.
        #expect(TranscriptionVocabulary.correcting("Hablé con borja ayer.", terms: ["Borja"])
            == "Hablé con Borja ayer.")
        // Capitalized mid-sentence: short exact and fuzzy matches still apply.
        #expect(TranscriptionVocabulary.correcting("Ayer vino Pena.", terms: ["Peña"]) == "Ayer vino Peña.")
        #expect(TranscriptionVocabulary.correcting("Hablé con Borla ayer.", terms: ["Borja"])
            == "Hablé con Borja ayer.")
        // Lowercase-initial terms are not guarded.
        #expect(TranscriptionVocabulary.correcting("Usa iphone.", terms: ["iPhone"]) == "Usa iPhone.")
    }

    // Regressions for audit C4: a manual fix is literal, never parsed as a
    // vocabulary line and never fuzzy-matched.
    @Test func manualReplacementIsLiteralAndWholeWord() {
        #expect(TranscriptionVocabulary.replacingLiteral(
            "sí, claro", with: "Sí, claro.", in: "Dijo sí, claro, y luego claro que sí."
        ) == "Dijo Sí, claro., y luego claro que sí.")
        #expect(TranscriptionVocabulary.replacingLiteral(
            "pausa larga", with: "causa", in: "Hubo una pausa larga. Otra pausa."
        ) == "Hubo una causa. Otra pausa.")
        #expect(TranscriptionVocabulary.replacingLiteral("ana", with: "Ana", in: "Ana y ana, pero no banana.")
            == "Ana y Ana, pero no banana.")
        // Template metacharacters in the replacement stay literal.
        #expect(TranscriptionVocabulary.replacingLiteral("x", with: "$0 \\1", in: "a x b") == "a $0 \\1 b")
    }

    @Test func onlySeparatorFreeFixesBecomeAliases() {
        #expect(TranscriptionVocabulary.canRememberAlias(canonical: "Gorosabel", variant: "gorosbel"))
        #expect(TranscriptionVocabulary.canRememberAlias(canonical: "Ion Azpeitia", variant: "Ionazpeitia"))
        #expect(!TranscriptionVocabulary.canRememberAlias(canonical: "Sí, claro.", variant: "sí, claro"))
        #expect(!TranscriptionVocabulary.canRememberAlias(canonical: "10:30", variant: "diez y media"))
        #expect(!TranscriptionVocabulary.canRememberAlias(canonical: "A = B", variant: "ab"))
    }

    /// Bench, MTPL meeting: OP10A and OP20s were rewritten to OP20A.
    @Test func neverFuzzyMatchesCodesWithDigits() {
        let terms = ["OP10", "OP20A", "AVEVA: Aviva"]
        let input = "OP10A uses DHCP, OP20s and OP10s are off, see the Aviva log."
        #expect(TranscriptionVocabulary.correcting(input, terms: terms)
            == "OP10A uses DHCP, OP20s and OP10s are off, see the AVEVA log.")
    }
}
