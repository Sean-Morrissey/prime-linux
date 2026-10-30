#!/usr/bin/env python3
"""make-terminal-logo.py — the terminal greeting's logo: the PRIME wordmark with
what it stands for underneath.

    ██████╗ ██████╗ ██╗███╗   ███╗███████╗
    ...                                       (blue-to-violet, one colour per row)

      Please Relax I'll Manage Everything     (the initials in the brand colours)

Writes, next to this file's ../terminal/ folder:

    prime-logo.txt        truecolor ANSI (what fastfetch shows)
    prime-logo.plain.txt  the same, no colour (for logs, `cat`, screen readers)

The fastfetch config (layer/seed/fastfetch/config.jsonc) uses the size printed at
the end, and the vertical padding that centres the logo against its module list.

    python3 layer/branding/src/make-terminal-logo.py
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "terminal")

WORDMARK = [
    "██████╗ ██████╗ ██╗███╗   ███╗███████╗",
    "██╔══██╗██╔══██╗██║████╗ ████║██╔════╝",
    "██████╔╝██████╔╝██║██╔████╔██║█████╗",
    "██╔═══╝ ██╔══██╗██║██║╚██╔╝██║██╔══╝",
    "██║     ██║  ██║██║██║ ╚═╝ ██║███████╗",
    "╚═╝     ╚═╝  ╚═╝╚═╝╚═╝     ╚═╝╚══════╝",
]
# one colour per wordmark row, sapphire to amethyst
GRADIENT = [(96, 165, 250), (115, 158, 250), (134, 152, 251),
            (154, 145, 251), (173, 139, 252), (192, 132, 252)]
WORDS = ["Please", "Relax", "I'll", "Manage", "Everything"]
# the initial of each word takes a brand colour (P..E across the gradient)
INITIALS = [GRADIENT[0], GRADIENT[1], GRADIENT[2], GRADIENT[4], GRADIENT[5]]
DIM, RESET = "\x1b[38;2;161;161;170m", "\x1b[0m"


def fg(rgb):
    return "\x1b[1;38;2;{};{};{}m".format(*rgb)


def build():
    width = max(len(l) for l in WORDMARK)
    tagline = " ".join(WORDS)
    pad = " " * ((width - len(tagline)) // 2)
    ansi = [f"{fg(c)}{line}{RESET}" for line, c in zip(WORDMARK, GRADIENT)]
    plain = list(WORDMARK)
    ansi.append("")
    plain.append("")
    ansi.append(pad + " ".join(f"{fg(c)}{w[0]}{RESET}{DIM}{w[1:]}{RESET}" for w, c in zip(WORDS, INITIALS)))
    plain.append(pad + tagline)
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
