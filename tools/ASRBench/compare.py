"""Compare app transcripts against a stronger reference transcript.

Usage:
  python compare.py --ref REF_DIR [--ref2 REF2_DIR] --hyp TransLocal=path.txt --hyp QuickSubs=path.srt \
      [--terms terms.txt] [--gold gold.txt] --out report.md

Hypotheses: TransLocal `[mm:ss] text` lines, SRT or WebVTT.
REF_DIR / REF2_DIR: folders written by reference.py (reference.json with word times).
--ref2: an independent second model. Only words both references agree on count
        towards "confirmed WER", so one model's mistakes don't punish an app.
--gold: hand-corrected excerpts, blocks of "[mm:ss-mm:ss]" followed by the text.
        Measures the reference itself, and the apps on those excerpts.
--terms: one term per line (names, codes); counted in reference vs each app.

The reference is another model, not the truth: the report says so.
"""
import argparse, json, re, unicodedata
from pathlib import Path

import jiwer

FILLERS = {"uh", "um", "uhm", "erm", "eh", "ah", "hmm", "mm", "mhm", "huh", "oh"}
SPELLING = {"okay": "ok", "alright": "all right", "percent": "%"}

# Number words -> digits (English and Spanish), so "OP fifty" == "OP50".
_UNITS_EN = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
_TENS_EN = {"twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90}
_UNITS_ES = "cero uno dos tres cuatro cinco seis siete ocho nueve diez once doce trece catorce quince dieciseis diecisiete dieciocho diecinueve veinte".split()
_TENS_ES = {"treinta": 30, "cuarenta": 40, "cincuenta": 50, "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90}
NUM_UNITS = {w: i for i, w in enumerate(_UNITS_EN)} | {w: i for i, w in enumerate(_UNITS_ES)} | {"un": 1, "una": 1}
NUM_TENS = _TENS_EN | _TENS_ES


def numbers_to_digits(words):
    out, i = [], 0
    while i < len(words):
        w = words[i]
        if w in NUM_TENS:
            value = NUM_TENS[w]
            j = i + 1
            if j < len(words) and words[j] == "y":  # "treinta y dos"
                j += 1
            if j < len(words) and words[j] in NUM_UNITS and 0 < NUM_UNITS[words[j]] < 10:
                value += NUM_UNITS[words[j]]
                i = j
            out.append(str(value))
        elif w in NUM_UNITS and w not in ("un", "una", "one") :
            out.append(str(NUM_UNITS[w]))
        else:
            out.append(w)
        i += 1
    return out


# ---------- parsing ----------

def clock(s: str) -> float:
    s = s.strip().replace(",", ".")
    parts = [float(p) for p in s.split(":")]
    t = 0.0
    for p in parts:
        t = t * 60 + p
    return t


def parse_hypothesis(path: Path):
    """Returns [(start, end or None, text)]."""
    raw = path.read_text(encoding="utf-8", errors="replace")
    segs = []
    if "-->" in raw:  # SRT / VTT
        for block in re.split(r"\n\s*\n", raw.replace("\r", "")):
            lines = [l for l in block.strip().split("\n") if l.strip()]
            for i, l in enumerate(lines):
                if "-->" in l:
                    a, b = l.split("-->")
                    b = b.strip().split(" ")[0]
                    text = " ".join(lines[i + 1:])
                    text = re.sub(r"<[^>]+>", "", text)
                    if text.strip():
                        segs.append((clock(a), clock(b), text))
                    break
        return segs
    pending = None
    for line in raw.split("\n"):
        m = re.match(r"\s*\[(\d{1,2}(?::\d{2}){1,2})\]\s*(.*)", line)
        if m:
            if pending:
                segs.append(pending)
            pending = [clock(m.group(1)), None, m.group(2)]
        elif line.strip():
            if pending:
                pending[2] += " " + line.strip()
            else:
                pending = [0.0, None, line.strip()]
    if pending:
        segs.append(pending)
    for i in range(len(segs) - 1):
        segs[i][1] = segs[i + 1][0]
    return [tuple(s) for s in segs]


def load_reference(folder: Path):
    """Returns (words [(word, start, end)], meta)."""
    data = json.loads((folder / "reference.json").read_text())
    words = []
    for seg in data.get("segments") or []:
        for w in seg.get("words") or []:
            words.append((w.get("text") or w.get("word"), w.get("start"), w.get("end")))
        if not seg.get("words") and seg.get("text"):
            words.append((seg["text"], seg.get("start"), seg.get("end")))
    if not words:
        for w in data.get("words") or data.get("timestamps") or []:
            words.append((w.get("text") or w.get("word"), w.get("start"), w.get("end")))
    if not words:
        words = [(t, None, None) for t in data.get("text", "").split()]
    return words, data.get("_meta", {})


# ---------- normalization ----------

def fold(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn")


def norm_tokens(text: str):
    t = fold(text.lower().replace("’", "'"))
    t = re.sub(r"[\*\[\(][^\*\]\)]*[\*\]\)]", " ", t)  # *sigh*, [music], (laughs)
    t = re.sub(r"(?<=\w)-(?=\w)", " ", t)
    t = re.sub(r"[^\w\s'%]", " ", t)
    t = re.sub(r"(?<=[a-z])(?=\d)|(?<=\d)(?=[a-z])", " ", t)  # op10b -> op 10 b
    out = []
    for w in t.split():
        w = w.strip("'")
        if w.endswith("'s"):
            w = w[:-2]
        if not w or w in FILLERS:
            continue
        w = SPELLING.get(w, w)
        out.extend(w.split())
    return numbers_to_digits(out)


def timed_tokens(words):
    """Reference words -> normalized tokens with times."""
    toks = []
    for w, s, e in words:
        for t in norm_tokens(w or ""):
            toks.append((t, s, e))
    return toks


def hyp_tokens(segs):
    """App segments -> tokens with an estimated time (spread within the line)."""
    toks = []
    for start, end, text in segs:
        ws = norm_tokens(text)
        span = (end - start) if end and end > start else 2.0 * max(len(ws), 1) / 5
        for i, w in enumerate(ws):
            toks.append((w, start + span * i / max(len(ws), 1)))
    return toks


# ---------- alignment ----------

def align(ref, hyp):
    """Per reference token: 'ok' | 'sub' | 'del'; insertions attached to the previous ref token."""
    out = jiwer.process_words(" ".join(ref), " ".join(hyp))
    status = ["ok"] * len(ref)
    ins_after = [0] * (len(ref) + 1)
    ins_runs = []  # (ref_index, hyp_start, hyp_end)
    for chunk in out.alignments[0]:
        if chunk.type == "equal":
            continue
        if chunk.type == "substitute":
            for i in range(chunk.ref_start_idx, chunk.ref_end_idx):
                status[i] = "sub"
        elif chunk.type == "delete":
            for i in range(chunk.ref_start_idx, chunk.ref_end_idx):
                status[i] = "del"
        elif chunk.type == "insert":
            n = chunk.hyp_end_idx - chunk.hyp_start_idx
            ins_after[chunk.ref_start_idx] += n
            ins_runs.append((chunk.ref_start_idx, chunk.hyp_start_idx, chunk.hyp_end_idx))
    return status, ins_after, ins_runs


def fmt(t):
    if t is None:
        return "?"
    t = int(t)
    return f"{t // 60:02d}:{t % 60:02d}"


def runs(flags, min_len):
    """Consecutive True runs of at least min_len: [(start, end_exclusive)]."""
    res, i = [], 0
    while i < len(flags):
        if flags[i]:
            j = i
            while j < len(flags) and flags[j]:
                j += 1
            if j - i >= min_len:
                res.append((i, j))
            i = j
        else:
            i += 1
    return res


def count_phrase(tokens, phrase):
    p = norm_tokens(phrase)
    if not p:
        return 0
    n = len(p)
    return sum(1 for i in range(len(tokens) - n + 1) if tokens[i:i + n] == p)


# ---------- gold ----------

def parse_gold(path: Path):
    blocks = []
    cur = None
    for line in path.read_text(encoding="utf-8").split("\n"):
        m = re.match(r"\s*\[(\d{1,2}:\d{2}(?::\d{2})?)\s*-\s*(\d{1,2}:\d{2}(?::\d{2})?)\]\s*(.*)", line)
        if m:
            cur = [clock(m.group(1)), clock(m.group(2)), m.group(3)]
            blocks.append(cur)
        elif cur and line.strip() and not line.lstrip().startswith("#"):
            cur[2] += " " + line.strip()
    return blocks


def window(tokens, a, b, margin=1.5):
    return [t[0] for t in tokens if t[1] is not None and a - margin <= t[1] < b + margin]


def wer(ref, hyp):
    if not ref:
        return float("nan")
    return jiwer.wer(" ".join(ref), " ".join(hyp)) if hyp else 1.0


# ---------- report ----------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", type=Path, required=True)
    ap.add_argument("--ref2", type=Path)
    ap.add_argument("--hyp", action="append", required=True, help="Name=path")
    ap.add_argument("--terms", type=Path)
    ap.add_argument("--gold", type=Path)
    ap.add_argument("--gold-template", type=Path,
                    help="write the 2-minute windows where systems disagree most, prefilled with the reference, to correct by ear")
    ap.add_argument("--gold-count", type=int, default=3)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--title", default="")
    a = ap.parse_args()

    ref_words, meta = load_reference(a.ref)
    ref = timed_tokens(ref_words)
    ref_t = [t[0] for t in ref]
    hyps = {}
    for spec in a.hyp:
        name, path = spec.split("=", 1)
        hyps[name] = hyp_tokens(parse_hypothesis(Path(path).expanduser()))

    confirmed = [True] * len(ref)
    ref2_meta = None
    r2 = None
    if a.ref2:
        r2_words, ref2_meta = load_reference(a.ref2)
        r2 = [t[0] for t in timed_tokens(r2_words)]
        st, _, _ = align(ref_t, r2)
        confirmed = [s == "ok" for s in st]

    L = []
    L.append(f"# Transcription comparison{(' — ' + a.title) if a.title else ''}\n")
    L.append(f"- Reference: `{meta.get('model', '?')}`, language {meta.get('language') or 'auto'}, "
             f"{meta.get('processing', 0):.0f} s to process {fmt(meta.get('seconds'))} of audio.")
    if ref2_meta:
        L.append(f"- Second reference: `{ref2_meta.get('model', '?')}`. The two agree on "
                 f"**{sum(confirmed) / max(len(ref), 1):.0%}** of the reference words; "
                 "only those count in *confirmed WER*.")
    L.append("- **The reference is another model, not the truth.** Absolute WER is an upper bound "
             "of the app's error; the difference between apps is what matters.")
    L.append("- Normalized: lowercase, no punctuation, no fillers (uh, um…), no sound tags.\n")

    L.append("## Summary\n")
    head = "| | WER vs ref | Confirmed WER | Subs | Missing | Inserted | Missing speech ≥ 8 words | Inserted runs ≥ 6 words | Words |"
    L.append(head)
    L.append("|" + "---|" * (head.count("|") - 1))
    details = {}
    for name, toks in hyps.items():
        ht = [t[0] for t in toks]
        st, ins_after, ins_runs = align(ref_t, ht)
        n = len(ref_t)
        subs, dels, ins = st.count("sub"), st.count("del"), sum(ins_after)
        cn = sum(confirmed)
        cerr = sum(1 for s, c in zip(st, confirmed) if c and s != "ok")
        cins = sum(ins_after[i] for i in range(n) if confirmed[i])
        miss = runs([s == "del" for s in st], 8)
        big_ins = [r for r in ins_runs if r[2] - r[1] >= 6]
        details[name] = (st, miss, big_ins, ht, toks)
        L.append(f"| **{name}** | {(subs + dels + ins) / max(n, 1):.1%} | "
                 f"{(cerr + cins) / max(cn, 1):.1%} | {subs} | {dels} | {ins} | "
                 f"{len(miss)} ({sum(b - a for a, b in miss)} words) | {len(big_ins)} | {len(ht)} |")
    L.append(f"\nReference: {len(ref_t)} words.\n")

    # Pairwise distance: how far apart every system is, including the two references.
    systems = {"Ref: " + meta.get("model", "ref").split("/")[-1]: ref_t}
    if r2 is not None:
        systems["Ref 2: " + ref2_meta.get("model", "ref2").split("/")[-1]] = r2
    systems |= {n: details[n][3] for n in hyps}
    L.append("## Distance between systems (WER, row taken as reference)\n")
    L.append("| | " + " | ".join(systems) + " |")
    L.append("|---|" + "---|" * len(systems))
    for rn, rt in systems.items():
        cells = ["—" if rn == hn else f"{jiwer.wer(' '.join(rt), ' '.join(ht)):.1%}" for hn, ht in systems.items()]
        L.append(f"| {rn} | " + " | ".join(cells) + " |")
    L.append("\nIf two strong models are as far apart as an app is from them, the reference cannot rank that app: "
             "only hand-corrected excerpts can.\n")

    # Where the errors are, per 2-minute window.
    L.append("## Errors per 2 minutes\n")
    L.append("| Window | Ref words | " + " | ".join(hyps) + " |")
    L.append("|---|---|" + "---|" * len(hyps))
    end = max((t[1] or 0) for t in ref) if ref else 0
    w0 = 0
    while w0 <= end:
        idx = [i for i, t in enumerate(ref) if t[1] is not None and w0 <= t[1] < w0 + 120]
        if idx:
            cells = []
            for name in hyps:
                st = details[name][0]
                e = sum(1 for i in idx if st[i] != "ok")
                cells.append(f"{e / len(idx):.0%}")
            L.append(f"| {fmt(w0)}–{fmt(w0 + 120)} | {len(idx)} | " + " | ".join(cells) + " |")
        w0 += 120

    for name, (st, miss, big_ins, ht, toks) in details.items():
        L.append(f"\n## {name}: missing speech and insertions\n")
        if not miss and not big_ins:
            L.append("None above the thresholds.")
        for a_, b_ in miss[:15]:
            text = " ".join(ref_t[a_:b_])
            L.append(f"- **Missing** {fmt(ref[a_][1])}–{fmt(ref[b_ - 1][2] or ref[b_ - 1][1])} "
                     f"({b_ - a_} words): “{text[:160]}{'…' if len(text) > 160 else ''}”")
        for ri, h0, h1 in big_ins[:15]:
            at = ref[min(ri, len(ref) - 1)][1] if ref else None
            text = " ".join(ht[h0:h1])
            L.append(f"- **Inserted** near {fmt(at)} ({h1 - h0} words): “{text[:160]}{'…' if len(text) > 160 else ''}”")

    if a.terms and a.terms.exists():
        terms = [l.strip() for l in a.terms.read_text().split("\n") if l.strip() and not l.startswith("#")]
        L.append("\n## Terms (count in reference vs each app)\n")
        L.append("| Term | Reference | " + " | ".join(hyps) + " |")
        L.append("|---|---|" + "---|" * len(hyps))
        for term in terms:
            canonical = term.split(":")[0].strip()
            r = count_phrase(ref_t, canonical)
            cells = [str(count_phrase(details[n][3], canonical)) for n in hyps]
            L.append(f"| {canonical} | {r} | " + " | ".join(cells) + " |")
        L.append("\nA count is not accuracy: it only says the spelling appears. Check the low ones by ear.")

    if a.gold and a.gold.exists():
        blocks = parse_gold(a.gold)
        L.append("\n## Hand-corrected excerpts (the only real ground truth)\n")
        L.append("| Excerpt | Words | Reference | " + " | ".join(hyps) + " |")
        L.append("|---|---|---|" + "---|" * len(hyps))
        tot = {k: [0, 0] for k in ["Reference", *hyps]}
        for s, e, text in blocks:
            g = norm_tokens(text)
            row = [fmt(s) + "–" + fmt(e), str(len(g))]
            for k, toks in [("Reference", [(t[0], t[1]) for t in ref]), *[(n, details[n][4]) for n in hyps]]:
                w = window(toks, s, e)
                v = wer(g, w)
                row.append(f"{v:.1%}")
                tot[k][0] += v * len(g)
                tot[k][1] += len(g)
            L.append("| " + " | ".join(row) + " |")
        L.append("| **All** | " + str(tot["Reference"][1]) + " | " +
                 " | ".join(f"**{tot[k][0] / max(tot[k][1], 1):.1%}**" for k in ["Reference", *hyps]) + " |")
        L.append("\nExcerpt edges are cut by time, so a word or two at each edge may count as an error for everyone.")

    if a.gold_template:
        # Score each 2-minute window by disagreement (references and apps), pick the worst ones.
        status_lists = [details[n][0] for n in hyps]
        if r2 is not None:
            status_lists.append(align(ref_t, r2)[0])
        scored = []
        end_t = max((t[1] or 0) for t in ref) if ref else 0
        w = 0
        while w <= end_t:
            idx = [i for i, t in enumerate(ref) if t[1] is not None and w <= t[1] < w + 120]
            if len(idx) >= 60:
                dis = sum(sum(1 for i in idx if st[i] != "ok") for st in status_lists) / (len(idx) * len(status_lists))
                scored.append((dis, w, idx))
            w += 120
        picks = sorted(sorted(scored, reverse=True)[:a.gold_count], key=lambda x: x[1])
        out = ["# Correct each block by ear, keeping its [start-end] line. Delete words that are not said,",
               "# add the ones that are missing. Names and codes as they should be written. Lines with # are ignored.", ""]
        for dis, w, idx in picks:
            out.append(f"# disagreement {dis:.0%}")
            out.append(f"[{fmt(w)}-{fmt(w + 120)}]")
            words = [ref_words_i for ref_words_i in ref_words if ref_words_i[1] is not None and w <= ref_words_i[1] < w + 120]
            out.append(" ".join(x[0] for x in words))
            out.append("")
        a.gold_template.write_text("\n".join(out))
        L.append(f"\nGold template written to `{a.gold_template}` ({len(picks)} excerpts).")

    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text("\n".join(L) + "\n")
    print(a.out)


if __name__ == "__main__":
    main()
