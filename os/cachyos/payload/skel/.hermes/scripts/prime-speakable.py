#!/usr/bin/env python3
"""Turn a markdown/LaTeX reply into something a human should hear.

The voice path used to read the raw reply, so @USER@ got "dollar, dollar, five,
dollar, two, dash, dash" out of `$y^2 - 10y + 25$`, plus tables read line by
line and a 1400-character lecture. Two jobs, both here:

  1. STRIP — no math, no tables, no code, no markup, no symbols nobody says.
  2. CAP   — a spoken reply is a rundown, not the document. Default 350 chars,
             cut at a sentence boundary (PRIME_TTS_MAX_CHARS overrides).

Usage: prime-speakable.py <text-file>   (prints the speakable text; exits 0 even
if the input is empty, so the caller can decide)
"""
from __future__ import annotations

import os
import re
import sys
import unicodedata

MAX_CHARS = int(os.environ.get("PRIME_TTS_MAX_CHARS", "350"))

# Spoken-word replacements, longest first so "->" never half-matches.
#
# Order matters: every non-ASCII SYMBOL must be swapped to words here, because a
# multilingual edge voice reads a bare U+2212 "−" or a superscript "²" in
# whatever language it guesses — that is the "why are you speaking Spanish?"
# bug in its second form. Anything still non-ASCII after these swaps is scrubged
# out by scrub_foreign() below rather than handed to the engine.
SWAPS = [
    ("\\rightarrow", " to "), ("\\to", " to "), ("\\cdot", " times "),
    ("\\times", " times "), ("\\neq", " not equal to "), ("\\pm", " plus or minus "),
    ("\\le", " less than or equal to "), ("\\ge", " greater than or equal to "),
    ("->", " to "), ("=>", " so "), ("→", ", "), ("⇒", ", "),
    ("✓", ""), ("✅", ""), ("·", " "), ("×", " times "), ("÷", " divided by "),
    ("—", ", "), ("–", ", "), ("…", "..."), ("%", " percent"), ("&", " and "),
    ("≈", " approximately "), ("≠", " not equal to "),
    # math symbols a person says out loud
    ("⁻", " to the minus "), ("⁰", " to the zero "), ("¹", " to the first "),
    ("²", " squared"), ("³", " cubed"), ("⁴", " to the fourth"),
    ("⁵", " to the fifth"), ("⁶", " to the sixth"), ("⁷", " to the seventh"),
    ("⁸", " to the eighth"), ("⁹", " to the ninth"),
    ("−", " minus "), ("±", " plus or minus "), ("√", " square root of "),
    ("∞", " infinity "), ("°", " degrees "), ("≡", " is identical to "),
    ("∑", " sum of "), ("∏", " product of "), ("∫", " integral of "),
    ("≤", " at most "), ("≥", " at least "), ("∈", " in "), ("π", " pi "),
    ("=", " equals "), ("+", " plus "),
]

# Typographic punctuation is fine to say — map it to ASCII before the scrub.
FOLD = {"’": "'", "‘": "'", "“": '"', "”": '"', "„": '"', "′": "'", "″": '"'}


def scrub_foreign(text: str) -> str:
    """Drop every character that is not printable ASCII.

    Multilingual edge voices switch language on foreign-looking tokens, and the
    desktop surfaces leak Nerd Font private-use glyphs, emoji and the occasional
    pasted non-Latin word into a reply. Accented Latin letters are folded to their
    plain form (café -> cafe) so real English never loses a word; everything else
    that cannot be said in an English sentence is removed rather than guessed at.
    """
    for src, dst in FOLD.items():
        text = text.replace(src, dst)
    folded = unicodedata.normalize("NFKD", text)
    folded = "".join(ch for ch in folded if not unicodedata.combining(ch))
    return "".join(ch if 0x20 <= ord(ch) < 0x7F else " " for ch in folded)



def strip_blocks(text: str) -> str:
    text = re.sub(r"```.*?```", " ", text, flags=re.S)          # code fences
    text = re.sub(r"`([^`]*)`", r"\1", text)                     # inline code
    text = re.sub(r"!\[[^\]]*\]\([^)]*\)", " ", text)            # images
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)         # links
    text = re.sub(r"MEDIA:\S+", " ", text)                       # file cards
    text = re.sub(r"^\s*\|.*$", " ", text, flags=re.M)           # table rows
    text = re.sub(r"^\s*[-:]{3,}.*$", " ", text, flags=re.M)     # table rules
    return text


def strip_math(text: str) -> str:
    text = re.sub(r"\$\$.*?\$\$", " ", text, flags=re.S)         # display math
    text = re.sub(r"\$[^$\n]*\$", " ", text)                     # inline math
    text = re.sub(r"\\\(.*?\\\)", " ", text, flags=re.S)
    text = re.sub(r"\\\[.*?\\\]", " ", text, flags=re.S)
    return text


def strip_markup(text: str) -> str:
    text = re.sub(r"^\s{0,3}#{1,6}\s*", "", text, flags=re.M)    # headings
    text = re.sub(r"^\s*>\s?", "", text, flags=re.M)             # quotes
    text = re.sub(r"^\s*[-*+]\s+", "", text, flags=re.M)         # bullets
    text = re.sub(r"^\s*\d+[.)]\s+", "", text, flags=re.M)       # numbered lists
    text = re.sub(r"\*\*([^*]*)\*\*", r"\1", text)               # bold
    text = re.sub(r"(?<!\w)\*([^*\n]+)\*(?!\w)", r"\1", text)    # italics
    text = re.sub(r"(?<!\w)_([^_\n]+)_(?!\w)", r"\1", text)      # italics
    text = re.sub(r"\\[a-zA-Z]+\*?", " ", text)                  # leftover TeX cmds
    return text


def tidy(text: str) -> str:
    for old, new in SWAPS:
        text = text.replace(old, new)
    text = re.sub(r"[\\{}]", " ", text)
    text = re.sub(r"[\x00-\x1f]+", " ", text)
    # Belt and braces: nothing non-ASCII reaches the voice engine.
    text = scrub_foreign(text)
    text = re.sub(r"\bequals\s+plus\b", "equals", text)      # "= +42" -> "= 42"
    text = re.sub(r"\bplus\s+plus\b", "plus", text)
    text = re.sub(r"\bequals\s+equals\b", "equals", text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\s+([,.;!?])", r"\1", text)      # no "word ," from swaps
    text = re.sub(r"\s*:\s*", ". ", text)            # a colon is just a pause
    text = re.sub(r"\s*\n\s*", ". ", text)           # blank line = pause
    text = re.sub(r"\.\s*\.", ".", text)
    text = re.sub(r"(\.\s*)+", ". ", text)
    return text.strip(" .") + ("." if text.strip() else "")


def cap(text: str, limit: int = MAX_CHARS) -> str:
    if len(text) <= limit:
        return text
    head = text[:limit]
    cut = max(head.rfind(". "), head.rfind("? "), head.rfind("! "))
    if cut < limit * 0.4:            # no good sentence boundary: use the last clause
        cut = max(head.rfind(", "), head.rfind("; "))
    if cut < limit * 0.4:
        cut = head.rfind(" ")
    return head[:cut].rstrip(" ,;") + "."


def speakable(raw: str) -> str:
    text = strip_blocks(raw)
    text = strip_math(text)
    text = strip_markup(text)
    return cap(tidy(text))


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: prime-speakable.py <text-file>", file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
        raw = fh.read()
    out = speakable(raw)
    sys.stdout.write(out + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
