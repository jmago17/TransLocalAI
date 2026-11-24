"""Transcribe an audio file with HiTZ's bilingual Basque + Spanish model.

Usage: python hitz.py AUDIO OUT_DIR [--model PATH.nemo] [--window 25]
Writes OUT_DIR/transcript.txt ("[mm:ss] text" per window) and summary.json.
Needs its own environment with NeMo (see README). Runs locally.

The model (HiTZ/BBS-S2TC_conformer_transducer_large, Apache 2.0) writes
lowercase text without punctuation and has no notion of long audio, so the
file is cut into windows at the quietest point near each boundary.
"""
import argparse, json, subprocess, tempfile, time
from pathlib import Path
import numpy as np
import soundfile as sf



def load_pcm16k(path: Path) -> np.ndarray:
    """afconvert decodes whatever CoreAudio reads; soundfile reads its WAV on any Python."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "a.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(path), str(wav)], check=True)
        samples, _ = sf.read(wav, dtype="float32")
    return samples

RATE = 16000
DEFAULT_MODEL = Path.home() / "Library/Caches/TransLocalAI-ASRBench-models/hitz/BBS-S2TC_conformer_transducer_large.nemo"


def cut_points(audio: np.ndarray, window: float, search: float = 4.0) -> list[int]:
    """Window boundaries, each moved to the quietest 0.2 s within `search` seconds before it."""
    points, start, hop = [0], 0, int(0.2 * RATE)
    while start + int(window * RATE) < len(audio):
        target = start + int(window * RATE)
        lo = target - int(search * RATE)
        frames = [(float(np.mean(audio[i:i + hop] ** 2)), i) for i in range(lo, target, hop)]
        start = min(frames)[1] + hop // 2
        points.append(start)
    return points + [len(audio)]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("audio", type=Path)
    p.add_argument("out", type=Path)
    p.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    p.add_argument("--window", type=float, default=25.0)
    a = p.parse_args()

    import nemo.collections.asr as nemo_asr
    audio = load_pcm16k(a.audio)
    model = nemo_asr.models.EncDecRNNTBPEModel.restore_from(str(a.model), map_location="cpu")
    model.eval()

    points = cut_points(audio, a.window)
    started = time.time()
    with tempfile.TemporaryDirectory() as tmp:
        paths = []
        for index, (lo, hi) in enumerate(zip(points, points[1:])):
            path = Path(tmp) / f"{index:05d}.wav"
            sf.write(path, audio[lo:hi], RATE)
            paths.append(str(path))
        results = model.transcribe(audio=paths, batch_size=4, verbose=False)
    elapsed = time.time() - started

    lines = []
    for lo, result in zip(points, results):
        text = (result.text if hasattr(result, "text") else str(result)).strip()
        if text:
            seconds = lo // RATE
            lines.append(f"[{seconds // 60:02d}:{seconds % 60:02d}] {text}")
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / "transcript.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    words = sum(len(line.split()) - 1 for line in lines)
    summary = {"model": a.model.name, "audioSeconds": len(audio) / RATE, "processingTime": elapsed,
               "windows": len(points) - 1, "words": words}
    (a.out / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
