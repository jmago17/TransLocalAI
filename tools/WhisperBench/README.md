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
| `BENCH_LANGUAGE=detect` | run the app's language survey first, as auto-detect does |
| `BENCH_ENGINE=apple` | the app's Apple Speech path instead of Whisper (`BENCH_LANGUAGE` is then a locale, e.g. `es-ES`); writes only `transcript.txt` |
| `BENCH_MODEL` | `openai_whisper-large-v3-v20240930_626MB` (the app's model, large-v3 turbo) |
| `BENCH_PROFILE` | `Balanced` (`Fast`, `Maximum coverage`) |
| `BENCH_VOCABULARY` | the app's built-in defaults; or a file in the app's line format |
| `BENCH_WATCH` | none; a file of spellings to count (one per line, `#` comments) |
| `BENCH_MODEL_BASE` | `~/Library/Caches/TransLocalAI-WhisperBench` (626 MB, downloaded once) |

To compare runs, copy a run's `summary.json` to `$BENCH_OUT/baseline.json`.

Timings come from a Mac's Neural Engine, not an iPhone: use them to compare
runs with each other, not as phone performance. No word error rate without a
hand-corrected reference transcript.
