# ASRBench: TransLocal vs Quick Subs against a stronger model

Compares app transcripts (TransLocal `[mm:ss]` text, SRT or VTT) against reference transcripts from
models stronger than the apps' Whisper large-v3 turbo. Everything runs on the Mac (MLX); audio and
transcripts stay in `~/Developer/TransLocalAI-eval/`, outside git.

## Setup (once)

    python3 -m venv ~/Library/Caches/TransLocalAI-ASRBench-venv
    ~/Library/Caches/TransLocalAI-ASRBench-venv/bin/pip install mlx-qwen3-asr parakeet-mlx jiwer
    export HF_HUB_CACHE=~/Library/Caches/TransLocalAI-ASRBench-models   # ~8.5 GB of models

No ffmpeg needed: audio is decoded with `afconvert`.

## Per meeting

    PY=~/Library/Caches/TransLocalAI-ASRBench-venv/bin/python
    $PY reference.py meeting.m4a ref-qwen --language English --context "AVEVA Iñaki OP10 …"
    $PY reference.py meeting.m4a ref-parakeet --engine parakeet
    $PY compare.py --ref ref-qwen --ref2 ref-parakeet \
        --hyp TransLocal=translocal.txt --hyp QuickSubs=quicksubs.srt \
        --terms terms.txt --gold-template gold.txt --out report.md
    # correct gold.txt by ear, then rerun compare.py with --gold gold.txt

- **Qwen3-ASR 1.7B**: English and Spanish (and 12 more), takes a context of terms. ~6 min per 28 min on an M4.
- **Parakeet TDT 0.6B v3**: 25 European languages, independent second opinion. ~4 min per 28 min.
- **Neither supports Basque.** For Basque meetings only app-vs-app and gold excerpts are meaningful.

## HiTZ bilingual model (Basque + Spanish)

`hitz.py` runs `HiTZ/BBS-S2TC_conformer_transducer_large` (Apache 2.0, 478 MB, NeMo) as a candidate engine,
not as a reference. It needs its own Python 3.11 environment (NeMo does not install on 3.14):

    uv venv --python 3.11 ~/Library/Caches/TransLocalAI-HiTZ-venv
    uv pip install --python ~/Library/Caches/TransLocalAI-HiTZ-venv/bin/python "nemo_toolkit[asr]" soundfile
    # model file: ~/Library/Caches/TransLocalAI-ASRBench-models/hitz/BBS-S2TC_conformer_transducer_large.nemo
    ~/Library/Caches/TransLocalAI-HiTZ-venv/bin/python hitz.py meeting.m4a out-dir --window 10

Measured 2026-11-24 (see `estado.md`): proper written Basque, but trained on parliament sessions only —
on shop-floor meetings it drops about half the words, loses every technical term and writes lowercase
without punctuation. Not a replacement for Whisper.

## Reading the report

- *Confirmed WER* counts only words both references agree on.
- The distance matrix shows how far the two references are from each other. If that is as large as an
  app's distance to them, the reference cannot rank the app.
- The hand-corrected excerpts (`--gold`) are the only real ground truth, and they also score the references.
