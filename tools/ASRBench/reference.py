"""Transcribe an audio file with a stronger local model to use as a reference.

Usage: python reference.py AUDIO OUT_DIR [--model Qwen/Qwen3-ASR-1.7B] [--language English] [--context "terms"]
Writes OUT_DIR/reference.json (text, chunks, words with times) and reference.txt.
Everything runs locally; audio never leaves the Mac.
"""
import argparse, json, subprocess, sys, tempfile, time, wave
from pathlib import Path
import numpy as np


def load_pcm16k(path: Path) -> np.ndarray:
    """Decode any format CoreAudio reads (m4a, caf, mp3, wav) with afconvert."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "a.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(path), str(wav)], check=True)
        with wave.open(str(wav)) as w:
            frames = w.readframes(w.getnframes())
    return np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0


def plain(x):
    if isinstance(x, dict):
        return {k: plain(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [plain(v) for v in x]
    if hasattr(x, "__dict__"):
        return plain(vars(x))
    if isinstance(x, (np.floating, np.integer)):
        return x.item()
    return x


def transcribe_qwen(audio, a):
    import mlx_qwen3_asr as asr
    result = asr.transcribe(audio, model=a.model, language=a.language, context=a.context,
                            return_timestamps=True, return_chunks=True)
    return plain(result)


def transcribe_parakeet(audio, a):
    """Parakeet's loader needs ffmpeg; hand it the samples decoded by afconvert instead."""
    import mlx.core as mx
    import parakeet_mlx, parakeet_mlx.parakeet as pp
    samples = mx.array(audio)
    loader = lambda *_args, **_kw: samples
    pp.load_audio = loader
    parakeet_mlx.audio.load_audio = loader
    model = parakeet_mlx.from_pretrained(a.model)
    result = model.transcribe("decoded-in-memory.wav", chunk_duration=120, overlap_duration=15)
    segments = []
    for sentence in result.sentences:
        words, cur = [], None
        for tok in sentence.tokens:
            if cur is None or tok.text.startswith(" "):
                if cur:
                    words.append(cur)
                cur = {"text": tok.text.strip(), "start": tok.start, "end": tok.end}
            else:
                cur["text"] += tok.text
                cur["end"] = tok.end
        if cur:
            words.append(cur)
        segments.append({"text": sentence.text, "start": sentence.start, "end": sentence.end, "words": words})
    return {"text": result.text, "segments": segments}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("audio", type=Path)
    p.add_argument("out", type=Path)
    p.add_argument("--engine", choices=["qwen", "parakeet"], default="qwen")
    p.add_argument("--model", default=None, help="default: Qwen/Qwen3-ASR-1.7B or mlx-community/parakeet-tdt-0.6b-v3")
    p.add_argument("--language", default=None)
    p.add_argument("--context", default="")
    a = p.parse_args()

    a.model = a.model or ("Qwen/Qwen3-ASR-1.7B" if a.engine == "qwen" else "mlx-community/parakeet-tdt-0.6b-v3")
    audio = load_pcm16k(a.audio)
    start = time.time()
    data = transcribe_qwen(audio, a) if a.engine == "qwen" else transcribe_parakeet(audio, a)
    elapsed = time.time() - start
    a.out.mkdir(parents=True, exist_ok=True)
    data["_meta"] = {"engine": a.engine, "model": a.model, "language": a.language, "context": a.context,
                     "audio": a.audio.name, "seconds": len(audio) / 16000, "processing": elapsed}
    (a.out / "reference.json").write_text(json.dumps(data, ensure_ascii=False, indent=1))
    (a.out / "reference.txt").write_text(data.get("text", ""))
    print(f"done in {elapsed:.0f} s, {len(data.get('text', '').split())} words", file=sys.stderr)


if __name__ == "__main__":
    main()
