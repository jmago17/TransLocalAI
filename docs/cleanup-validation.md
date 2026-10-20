# TransLocalAI cleanup validation

Base: `b62cf06088ee5b93f570e6842636f46eb19fb2dd` (`origin/main`, fetched before editing).
Scope: TransLocalAI only. Independent checkout, branch `codex/translocal-cleanup`.
Original checkout and its untracked AGENTS.md, CLAUDE.md and estado.md were preserved.

## Changes

- Remove `AudioFileManager.isDownloaded` and `startDownloading`: repository-wide Swift searches found only their declarations. The latter only checked local existence and never downloaded anything. Inline the private directory getter into the existing public getter; keep the same path and directory creation behavior.
- Cache vocabulary decisions per original token **within one call**, including misses. Preserve alias ordering, phrase handling, fuzzy matching, tie breaking and UTF-16 range validation. Assemble replacements from the immutable source instead of repeatedly mutating the transcript.
- Add regressions for decomposed accents, emoji, non-Latin text, punctuation, changed replacement lengths, repeated hits/misses, ordered aliases, and changes of vocabulary between calls.
- Add a local storage lifecycle regression using unique filenames and tiny synthetic byte fixtures. Verify copy preserves its source, move removes it, replacement preserves exact bytes, resolution and repeated deletion.

No model, resource, schema, language catalog, recorder, export code or existing test was removed. `MacTranscriber` remains: it coordinates detection, preparation and transcription, rather than merely forwarding a call.

## Reproduce the performance comparison

From the repository root (use existing output directories):

```sh
mkdir -p /tmp/translocal-benchmark/before /tmp/translocal-benchmark/after
git show b62cf06088ee5b93f570e6842636f46eb19fb2dd:Core/TranscriptionVocabulary.swift > /tmp/translocal-benchmark/baseline.swift
swiftc -O /tmp/translocal-benchmark/baseline.swift scripts/VocabularyBenchmark.swift -o /tmp/translocal-benchmark/before-run
swiftc -O Core/TranscriptionVocabulary.swift scripts/VocabularyBenchmark.swift -o /tmp/translocal-benchmark/after-run
/tmp/translocal-benchmark/before-run /tmp/translocal-benchmark/before
/tmp/translocal-benchmark/after-run /tmp/translocal-benchmark/after
diff -ru /tmp/translocal-benchmark/before /tmp/translocal-benchmark/after
```

The harness warms each fixture and reports the median of five executions. It writes complete corrected outputs, so the comparison checks content rather than timing alone. The cache uses additional memory proportional to the number of distinct tokens; unique-token workloads have little opportunity to benefit. These are correction-only timings, not end-to-end transcription or model inference measurements.

## Validation

Final result: **macOS build passed; 21 native macOS tests passed; iOS build and 30 simulator tests passed (0 failures, 0 skips)**. Logs and xcresult bundles are retained in the sibling `validation` directory of the isolated checkout.

Final optimized benchmark, after builds finished (milliseconds, median of five):

| Fixture | Before | After |
| --- | ---: | ---: |
| Repeated transcript, 36,500 UTF-8 bytes, 100 terms | 41.155 | 1.799 |
| 2,000 unique tokens, 16,889 bytes, 100 terms | 16.375 | 16.648 |

All six fixture outputs were byte-identical (`diff -ru` returned 0). The repeated case is about 23 times faster; the unique case is about 1.7% slower. An additional alternating-order comparison in a single process (nine pairs, median) measured 40.958 → 1.845 ms and 16.304 → 16.439 ms, respectively. System load caused substantial earlier timing variation, so only the final measurements after compilation are reported here. The paired harness and measurements are also retained in `../validation`.

### Native macOS

`TranscriberMac` built successfully with Xcode 27.1 (27A9275):

```sh
xcodebuild -project Transcriber.xcodeproj -scheme TranscriberMac -configuration Debug -destination 'platform=macOS' -clonedSourcePackagesDirPath ../SourcePackages -derivedDataPath ../DerivedDataMacFinal -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build
```

21 Swift Testing tests passed on macOS. The Mac scheme has no test target, so a temporary Swift package (`../validation/MacRegression`) compiles symlinks to the production Vocabulary, TranscriptFileParser and AudioFileManager sources and the four corresponding repository test files, using Swift 5 language mode. This executes real production logic but is not a Mac UI or full transcription-engine test:

```sh
swift test --package-path ../validation/MacRegression --scratch-path /tmp/translocal-mac-regression-20261021 --cache-path ../validation/swift-cache
```

The initial package build in Documents passed 20 tests; its incremental retry hit codesign metadata errors. Moving build products to `/tmp` resolved that. A subsequent added test initially had an incorrect expectation about decomposed accents; comparing baseline and modified outputs established the same existing behavior, and the corrected regression passed. The standalone package reports the existing Swift 6 migration warning about AudioFileManager's stored FileManager; the app remains in Swift 5 mode.

### iOS Simulator

Dedicated iPhone 17 Pro / iOS 27.0 simulator: `93CDC8FA-EF0C-497B-9694-16FEC35E23E6`.

```sh
xcodebuild -project Transcriber.xcodeproj -scheme Transcriber -configuration Debug -destination 'platform=iOS Simulator,id=93CDC8FA-EF0C-497B-9694-16FEC35E23E6' -clonedSourcePackagesDirPath ../SourcePackages -derivedDataPath /tmp/translocal-ios-validation-20261021 -disableAutomaticPackageResolution -parallel-testing-enabled NO -resultBundlePath ../validation/ios-clean-tests.xcresult -only-testing:TranscriberTests/VocabularyCorrectionTests -only-testing:TranscriberTests/AudioFileManagerTests -only-testing:TranscriberTests/TranscriberTests -only-testing:TranscriberTests/SuspiciousVocabularyTests -only-testing:TranscriberTests/WhisperDecodingSupportTests -only-testing:TranscriberTests/WhisperModelSelectionTests CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
```

The first attempt compiled but the unsigned host could not initialize CloudKit entitlements; it was stopped after stalling. A signed retry in Documents failed codesign on generated resource metadata. The command above uses ad hoc signing and `/tmp` products, with no production project changes. It completed with `TEST SUCCEEDED`: 30 tests, 6 suites, 0 failures or skips. The simulator is shut down; other simulators were left alone.

### Limits

No giant models, paid external services, App Store Connect, microphone capture, real speech inference or live iCloud sync validation. Pure decoding-policy tests cover gap detection, segment merging and repetition filtering, not recognition quality. Existing AI/model-dependent tests are retained but excluded from this focused run. Import tests exercise SRT and segmented JSON; export and recording paths were not changed. No user data or other application checkout was modified.
