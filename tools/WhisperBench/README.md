# WhisperBench

Runs the app's own Whisper pipeline (`WhisperDecodingSupport.runPipeline`,
T4 cleanup, vocabulary corrections, SRT/VTT export) on one local audio file
and writes `eval_report.md`. The Core files are symlinks, so the bench always
measures the code the app ships. Not part of any app target.

    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
    swift build -c release
    BENCH_AUDIO=~/path/meeting.m4a BENCH_LABEL=t1-prompt .build/release/WhisperBench

| Variable | Default |
|---|---|
| `BENCH_AUDIO` | required |
| `BENCH_OUT` | `~/Developer/TransLocalAI-eval` (outside git: the transcripts are private) |
| `BENCH_LABEL` | timestamp; one sub-folder per run |
| `BENCH_LANGUAGE` | auto (the app's "multilingual") |
| `BENCH_PROFILE` | `Balanced` (`Fast`, `Maximum coverage`) |
| `BENCH_VOCABULARY` | the app's built-in defaults; or a file in the app's line format |
| `BENCH_WATCH` | none; a file of spellings to count (one per line, `#` comments) |
| `BENCH_MODEL_BASE` | `~/Library/Caches/TransLocalAI-WhisperBench` (626 MB, downloaded once) |

To compare runs, copy a run's `summary.json` to `$BENCH_OUT/baseline.json`.

Timings come from a Mac's Neural Engine, not an iPhone: use them to compare
runs with each other, not as phone performance. No word error rate without a
hand-corrected reference transcript.
