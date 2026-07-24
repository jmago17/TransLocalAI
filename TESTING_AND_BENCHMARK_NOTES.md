# Testing & benchmark backlog

Two separate tracks. **A** = unit tests to backfill inside `TranscriberTests`.
**B** = the model/profile comparison tool, which is **not** part of the app —
it lives as a standalone tool (script / CLI / separate executable), run
outside the shipping targets.

---

## A. Unit tests to add (in `TranscriberTests/TranscriptionPipelineTests.swift`)

All of these cover code we already shipped that currently has **zero**
coverage. Each is pure or near-pure and testable with swift-testing (`@Test`).

> **Shared-state gotcha:** the terminology store reads/writes the real App
> Group suite (`group.com.josumartinez.transcriber`) via `UserDefaults` +
> `TranscriptionVocabulary`. Every terminology test must **clean up after
> itself** (delete the terms it added) and should not assume an empty store.
> The existing `addUpdateAndDeleteTerm` / `importsPlainTextAndSkipsDuplicates`
> tests already do this — follow that pattern. Consider, as a follow-up,
> injecting a test-only suite name so these tests are fully isolated.

### 1. `SpeechTranscriptionManager.audioTimeRange(of:)` — the Spanish fix (highest priority)
This is the regression test for the bug just reported (Apple + Spanish lost
its `[mm:ss]` markers). No test exists.

- `import Speech`, `import CoreMedia`, `@testable import Transcriber`.
- **Whole-string case:** build `var a = AttributedString("hola")`, set
  `a.audioTimeRange = CMTimeRange(start: CMTime(seconds: 3, preferredTimescale: 600), duration: CMTime(seconds: 1, preferredTimescale: 600))`.
  Assert `audioTimeRange(of: a)?.start.seconds == 3`.
- **Multi-run case (the actual bug):** make two `AttributedString`s with
  *different* `audioTimeRange` values (e.g. starts 2 s and 4 s), `append` them
  into one. The whole-string `.audioTimeRange` convenience is `nil` here;
  assert `audioTimeRange(of: combined)?.start.seconds == 2` and
  `.end.seconds == 5` (last run's end). This is exactly the es-ES shape.
- **No-attribute case:** plain `AttributedString("x")` → returns `nil`.

### 2. `WhisperDecodingSupport.makeOptions` / `relaxedOptions` — profile thresholds
Guards the "Maximum coverage keeps more speech" claim. Requires
`import WhisperKit` (only compiles where `canImport(WhisperKit)`; wrap the test
body in `#if canImport(WhisperKit)`).

- `makeOptions(language: "es", profile: .balanced)`: assert
  `noSpeechThreshold == 0.6`, `logProbThreshold == -1.0`,
  `chunkingStrategy == .vad`.
- `.maximumCoverage`: assert `noSpeechThreshold == 0.8`,
  `logProbThreshold == -1.4`, and that both are strictly looser than
  `.balanced` (`> 0.6` / `< -1.0`), and `temperatureFallbackCount` is higher.
- `.fast`: `temperatureFallbackCount == 2`.
- `relaxedOptions(language:)`: `noSpeechThreshold == 0.9`,
  `firstTokenLogProbThreshold == nil`.

### 3. `TranscriptionTerminology.recordRecognitions` — the feedback loop
Never tested; this is the "terms that appear gain weight" mechanism.

- Add a distinctive term (`addTerm("Zorionak")`), call
  `recordRecognitions(in: "Kaixo Zorionak guztioi")`, then read the entry back
  from `entries` and assert `usageCount >= 1` and `lastUsedAt != nil`.
- Call it 3× and assert a built-in that started `.observed` graduates to
  `.suggested` (use a built-in like `"SCADA"` in the text). Clean up.
- Negative: a term NOT in the text keeps `usageCount == 0`.

### 4. `recordCorrection` — state escalation
Only referenced once today; the promotion path isn't asserted.

- One `recordCorrection(canonical: "Wallix", variant: "Wallace")` →
  entry state `.confirmed`, `correctionCount == 1`.
- Three corrections of the same canonical → state `.trusted`. Clean up.

### 5. `confirmTerm` — built-in promotion
- `confirmTerm(canonical: "SCADA")` (a built-in) → its entry is now
  `.confirmed` and appears in `rankedTerms(limit:)` ahead of unconfirmed
  built-ins. Reset with `setEnabled`/delete as appropriate.

### 6. `promptTokens` — token cap (needs a small refactor to be unit-testable)
`promptTokens(tokenizer:terms:)` takes a real `WhisperTokenizer`, which needs a
downloaded model — not unit-test friendly. **Recommended:** extract the pure
string-building step into a helper, e.g.
`glossaryPromptString(terms: [String]) -> String?`, and test that:
- empty terms → `nil`;
- non-empty → begins with `" Glossary: "`, comma-joined, ends with `.`.
Leave the token-count cap (`prefix(maxTokens)`) for the integration/benchmark
tool (B), where a real model is loaded.

---

## B. Model/profile comparison tool — standalone, NOT in the app

Decision (2026-07-24): this is **not** shipped inside the app. It is a separate
tool — a script or small CLI executable — that a developer runs against a
folder of sample recordings. It can live in `scripts/` or its own SPM
executable target; it must not be linked into `Transcriber` / `TranscriberMac`.

What it should do (Phases 6–7 of the original audit):

- Run the **same** recording through the matrix: Apple Fast, Apple Enhanced,
  Whisper Balanced, Whisper MaximumCoverage.
- Emit per run: TXT + JSON, processing time, realtime factor, retries,
  discarded chunks, coverage %, temporal gaps, confidence stats (the per-run
  `WhisperDecodingSupport.Metrics` already captures most of this — reuse it).
- **Scoring functions (the pure, testable core — worth writing test-first):**
  - word error rate vs a reference transcript;
  - coverage % and gap seconds;
  - terminology accuracy: expected terms recognized, exact-spelling accuracy,
    alias→canonical corrections applied, and **false glossary replacements**
    (a glossary term wrongly inserted where it didn't belong — the key
    regression guard for the correction layer);
  - repeated-phrase / hallucination-loop counts.
- Compare conditions: no terminology / built-in only / global confirmed /
  global + cleanup, per the terminology-eval spec.

Because it's external, it can depend on a fixtures folder of recordings +
hand-checked reference transcripts that never ship in the app bundle.
