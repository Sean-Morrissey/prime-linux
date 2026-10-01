#!/usr/bin/env python3
"""make-terminal-logo.py — the terminal greeting's logo: P.R.I.M.E, spelled down,
the words read across.

    P  lease
    R  elax
    I  'll
    M  anage
    E  verything

Each capital is a compact 3-row block letter (a 5x6 bitmap drawn with half blocks)
in the brand's blue-to-violet gradient, one colour per letter; the rest of the word
sits on the letter's middle row in bright text. Writes, next to this file's
../terminal/ folder:

    prime-logo.txt        truecolor ANSI (what fastfetch shows)
    prime-logo.plain.txt  the same shapes, no colour (for logs, `cat`, screen readers)

The fastfetch config (layer/seed/fastfetch/config.jsonc) uses the size printed at
the end, and the vertical padding that centres the logo against its module list.

    python3 layer/branding/src/make-terminal-logo.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "terminal")

# 5 wide x 6 tall; '#' is ink. Two bitmap rows make one text row (▀ ▄ █).
GLYPHS = {
    "P": ["####.", "#...#", "####.", "#....", "#....", "#...."],
    "R": ["####.", "#...#", "####.", "#.#..", "#..#.", "#...#"],
    "I": [".###.", "..#..", "..#..", "..#..", "..#..", ".###."],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#"],
    "E": ["#####", "#....", "####.", "#....", "#....", "#####"],
}
WORDS = [("P", "lease"), ("R", "elax"), ("I", "'ll"), ("M", "anage"), ("E", "verything")]
GRADIENT = [(96, 165, 250), (115, 158, 250), (134, 152, 251), (154, 145, 251), (192, 132, 252)]
GAP = "  "                                   # between the capital and the rest of the word
BRIGHT, RESET = "\x1b[1;97m", "\x1b[0m"


def rows(letter: str) -> list:
    bm = GLYPHS[letter]
    out = []
    for top, bot in zip(bm[0::2], bm[1::2]):
        out.append("".join("█" if a == "#" and b == "#" else "▀" if a == "#" else "▄" if b == "#" else " "
                           for a, b in zip(top, bot)))
    return out


def build():
    ansi, plain = [], []
    for (letter, rest), (r, g, b) in zip(WORDS, GRADIENT):
        colour = f"\x1b[38;2;{r};{g};{b}m"
        for i, line in enumerate(rows(letter)):
            tail = rest if i == 1 else ""
            plain.append((line + (GAP + tail if tail else "")).rstrip())
            ansi.append(f"{colour}{line}{RESET}" + (f"{GAP}{BRIGHT}{tail}{RESET}" if tail else ""))
    return ansi, plain


def main():
    ansi, plain = build()
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "prime-logo.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(ansi) + "\n")
    with open(os.path.join(OUT, "prime-logo.plain.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(plain) + "\n")
    width = max(len(l) for l in plain)
    print("\n".join(ansi))
    print(f"\n{len(plain)} lines tall, {width} columns wide")
    assert len(plain) <= 16 and width <= 40, "the logo must stay within 16 lines x 40 columns"


if __name__ == "__main__":
    main()
