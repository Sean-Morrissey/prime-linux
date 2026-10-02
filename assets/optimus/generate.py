#!/usr/bin/env python3
"""Draw Optimus Prime as coloured ASCII art.

Drawn from primitives to the character's design cues — blue helmet with side
antennae, silver faceplate, cyan eyes, and the truck-cab chest (red block, two
light-blue windows, central silver grille, gold trim). Nothing is traced from
anyone else's artwork.

Outputs (all in this directory):
  optimus-prime.ansi          truecolor half-blocks — terminals, MOTD, fastfetch
  optimus-prime.txt           plain ASCII, no colour — any terminal, any log
  optimus-prime.png           pixel-art preview of the drawing
  optimus-prime-terminal.png  what it looks like actually printed in a terminal

Run: python3 generate.py
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

W, H = 96, 64                      # logical pixels -> 96 x 32 text rows as half-blocks
HERE = Path(__file__).resolve().parent
FONT = "/usr/share/fonts/TTF/JetBrainsMonoNerdFontMono-Regular.ttf"

# ---- G1 Optimus palette
OUTLINE = (10, 16, 32)
BLUE_D, BLUE, BLUE_L = (18, 54, 128), (34, 92, 190), (96, 152, 232)
RED_D, RED, RED_L = (146, 20, 26), (201, 32, 38), (236, 74, 62)
SILVER, SILVER_D, GREY, GREY_D = (198, 204, 214), (150, 158, 172), (104, 112, 126), (66, 72, 84)
EYE, WINDOW, WINDOW_HI = (130, 232, 255), (156, 216, 255), (240, 250, 255)
GOLD = (214, 170, 74)

img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(img)


def rrect(box, fill, outline=OUTLINE, r=2, w=1):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=w)


def rect(box, fill, outline=OUTLINE, w=1):
    d.rectangle(box, fill=fill, outline=outline, width=w)


cx = W // 2  # 48

# ============================================================ one connected figure
# Order matters: the mass is drawn first, then each overlapping piece is filled on
# top of it, so there are no seams and nothing floats in space.

# --- body mass: shoulders, arms and chest as a single shape reaching the bottom
rrect([4, 42, 92, 64], fill=GREY, r=9, w=2)                # arms / shoulder mass
rrect([20, 44, 76, 64], fill=RED, r=5, w=2)                # chest block on top
d.rectangle([24, 46, 72, 52], fill=RED_L)                  # chest top light
rect([46, 50, 52, 64], SILVER, SILVER_D, 1)                # central grille column
for yy in range(52, 64, 2):
    d.line([(47, yy), (51, yy)], fill=SILVER_D)
rrect([26, 48, 44, 59], fill=WINDOW, r=1, w=1)             # truck window, left
rrect([54, 48, 72, 59], fill=WINDOW, r=1, w=1)             # truck window, right
d.polygon([(27, 49), (36, 49), (27, 54)], fill=WINDOW_HI)
d.polygon([(55, 49), (64, 49), (55, 54)], fill=WINDOW_HI)
d.line([(22, 62), (74, 62)], fill=GOLD)                    # gold trim
# shoulder caps: solid plates, no inner hole (an inner cut-out read as a wheel)
for x0 in (4, 76):
    rrect([x0, 42, x0 + 16, 56], fill=SILVER, r=5, w=2)
    rrect([x0 + 2, 44, x0 + 12, 50], fill=RED, r=2, w=1)
    rrect([x0 + 2, 54, x0 + 14, 64], fill=SILVER_D, r=3, w=1)   # arm below it

# --- neck, drawn before the head so the head covers its top
rect([41, 34, 55, 48], GREY_D)

# --- antennae: tapered fins, drawn BEFORE the helmet with NO outline of their own.
#     The helmet covers their inner edge, which welds them to the head instead of
#     leaving two floating bars; the taper is what stops them reading as big ears.
for x0, x1 in ((22, 34), (62, 74)):
    d.polygon([(x0, 34), (x1, 34), (x1 - 4, 6), (x0 + 4, 6)], fill=BLUE)
    d.polygon([(x0 + 2, 30), (x0 + 5, 30), (x0 + 5, 10), (x0 + 3, 10)], fill=BLUE_L)

# --- helmet dome (covers the antennae roots and the neck)
d.rounded_rectangle([30, 6, 66, 36], radius=15, fill=BLUE, outline=OUTLINE, width=2)
d.rectangle([30, 26, 66, 36], fill=BLUE)
d.rounded_rectangle([33, 10, 41, 34], radius=6, fill=BLUE_L)     # left light
d.rounded_rectangle([56, 12, 64, 34], radius=6, fill=BLUE_D)     # right shade
# raised centre ridge — blue and silver, not the red triangle that read as wrong
rrect([43, 4, 53, 14], fill=BLUE_L, outline=OUTLINE, r=3, w=1)
rect([46, 6, 50, 13], SILVER, SILVER_D, 1)

# --- faceplate, set into the helmet
rrect([36, 14, 60, 44], fill=SILVER, r=5, w=2)
rrect([38, 16, 58, 25], fill=SILVER_D, r=3, w=1)                 # brow
rrect([39, 21, 47, 27], fill=EYE, r=2, w=1)                      # eyes
rrect([49, 21, 57, 27], fill=EYE, r=2, w=1)
rect([41, 22, 44, 23], WINDOW_HI, WINDOW_HI, 1)
rect([51, 22, 54, 23], WINDOW_HI, WINDOW_HI, 1)
rrect([37, 28, 42, 42], fill=SILVER_D, r=2, w=1)                 # cheeks
rrect([54, 28, 59, 42], fill=SILVER_D, r=2, w=1)
rrect([43, 30, 53, 40], fill=SILVER, r=3, w=1)                   # mouthplate
d.line([(45, 32), (51, 32)], fill=SILVER_D)
d.line([(45, 36), (51, 36)], fill=SILVER_D)
rrect([41, 40, 55, 45], fill=SILVER_D, r=2, w=1)                 # chin
rect([36, 46, 60, 49], GREY, GREY_D, 1)                          # collar: inside the
#   chest edge, so it reads as the head's base rather than a bar running out to the
#   shoulders and ending in stray nubs

# ================================================================== output
px = img.load()
RESET = "\033[0m"


def fg(c):
    return f"\033[38;2;{c[0]};{c[1]};{c[2]}m"


def bg(c):
    return f"\033[48;2;{c[0]};{c[1]};{c[2]}m"


ansi_lines, plain_lines = [], []
RAMP = " .:-=+*#%@"


def lum(c):
    return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255


for y in range(0, H - 1, 2):
    ansi_row, plain_row = [], []
    for x in range(W):
        top, bot = px[x, y], px[x, y + 1]
        t = top if top[3] else None
        b = bot if bot[3] else None
        if t is None and b is None:
            ansi_row.append(" ")
        elif t is not None and b is None:
            ansi_row.append(fg(t) + "\u2580" + RESET)
        elif t is None and b is not None:
            ansi_row.append(fg(b) + "\u2584" + RESET)
        else:
            ansi_row.append(fg(t) + bg(b) + "\u2580" + RESET)
        vals = [p for p in (top, bot) if p[3]]
        plain_row.append(" " if not vals else RAMP[min(9, int(
            (sum(lum(p) for p in vals) / len(vals)) * 10))])
    ansi_lines.append("".join(ansi_row))
    plain_lines.append("".join(plain_row).rstrip())

(HERE / "optimus-prime.ansi").write_text("\n".join(ansi_lines) + "\n")
(HERE / "optimus-prime.txt").write_text("\n".join(plain_lines) + "\n")

# pixel-art preview
SCALE = 8
prev = img.resize((W * SCALE, H * SCALE), Image.NEAREST)
art = Image.new("RGB", prev.size, (13, 15, 21))
art = Image.alpha_composite(art.convert("RGBA"), prev).convert("RGB")   # no soft edges
art.save(HERE / "optimus-prime.png")

# terminal preview: the actual half-blocks, in a real monospace font with real colour
try:
    font = ImageFont.truetype(FONT, 18)
    cw = int(font.getlength("M")) or 10
    lh = 18
    term = Image.new("RGB", (cw * W, lh * len(ansi_lines)), (11, 12, 16))
    td = ImageDraw.Draw(term)
    for row, y in enumerate(range(0, H - 1, 2)):
        for x in range(W):
            top, bot = px[x, y], px[x, y + 1]
            t = top if top[3] else None
            b = bot if bot[3] else None
            if t is None and b is None:
                continue
            x0, y0 = x * cw, row * lh
            if b is not None:
                td.rectangle([x0, y0, x0 + cw, y0 + lh], fill=b[0:3])
                td.text((x0, y0), "\u2580", font=font, fill=t[0:3] if t else b[0:3])
            elif t is not None:
                td.text((x0, y0), "\u2580", font=font, fill=t[0:3])
    term.save(HERE / "optimus-prime-terminal.png")
    have_term = True
except Exception as exc:                                   # missing font, no PIL font
    have_term = False
    print(f"terminal preview skipped: {exc}")

print(f"wrote: optimus-prime.ansi           ({len(ansi_lines)} lines)")
print(f"wrote: optimus-prime.txt            ({len(plain_lines)} lines, plain)")
print(f"wrote: optimus-prime.png            ({art.size[0]}x{art.size[1]})")
if have_term:
    print(f"wrote: optimus-prime-terminal.png   ({term.size[0]}x{term.size[1]})")
