#!/usr/bin/env python3
"""Logo concept explorations for Prime Linux (original artwork, CC0).

Writes layer/branding/concepts/<name>.svg. #f87171 is the accent token.
"""
import math, os

A = "#f87171"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "concepts")


def f(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def P(*pts):
    return " ".join(f(x) for x in pts)


def wedge(c1, r1, c2, r2):
    """Tapered stroke: hull of two circles (the shape of a typographic prime)."""
    (x1, y1), (x2, y2) = c1, c2
    d = math.hypot(x2 - x1, y2 - y1)
    phi = math.atan2(y2 - y1, x2 - x1)
    al = math.acos((r1 - r2) / d)
    a1, a2 = phi + al, phi - al
    t1a = (x1 + r1 * math.cos(a1), y1 + r1 * math.sin(a1))
    t2a = (x2 + r2 * math.cos(a1), y2 + r2 * math.sin(a1))
    t1b = (x1 + r1 * math.cos(a2), y1 + r1 * math.sin(a2))
    t2b = (x2 + r2 * math.cos(a2), y2 + r2 * math.sin(a2))
    return (f"M{P(*t1a)} L{P(*t2a)} A{f(r2)} {f(r2)} 0 0 0 {P(*t2b)} "
            f"L{P(*t1b)} A{f(r1)} {f(r1)} 0 1 0 {P(*t1a)} Z")


def svg(body, note):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">\n'
            f'<!-- Prime Linux logo concept — {note}. Original artwork, CC0. -->\n{body}\n</svg>\n')


def concept_a(dx=-12):
    stem = "M70 44 H104 V212 H70 Z"
    bowl = "M104 44 H134 A62 62 0 0 1 134 168 H104 V134 H134 A28 28 0 0 0 134 78 H104 Z"
    tick = wedge((206, 54), 16, (190, 108), 5)
    return f'<g transform="translate({dx} 0)" fill="{A}"><path d="{stem} {bowl}"/><path d="{tick}"/></g>'


def concept_b():
    w = wedge((150, 66), 30, (112, 192), 9)
    return f'<circle cx="128" cy="128" r="116" fill="{A}"/><path d="{w}" fill="#fff"/>'


def concept_c():
    return (f'<defs><clipPath id="d"><circle cx="128" cy="128" r="116"/></clipPath>'
            f'<clipPath id="up"><rect x="0" y="0" width="256" height="140"/></clipPath></defs>'
            f'<g clip-path="url(#d)"><rect width="256" height="256" fill="{A}"/>'
            f'<rect y="152" width="256" height="104" fill="#000" fill-opacity="0.28"/>'
            f'<circle cx="128" cy="152" r="56" fill="#fff" clip-path="url(#up)"/>'
            f'<rect x="88" y="166" width="80" height="10" rx="5" fill="#fff" fill-opacity="0.7"/>'
            f'<rect x="106" y="188" width="44" height="10" rx="5" fill="#fff" fill-opacity="0.45"/></g>')


def concept_d():
    bowl = "M60 40 H132 A64 64 0 0 1 132 168 H100 V128 H132 A24 24 0 0 0 132 80 H60 Z"
    stem = "M60 40 H100 V216 H60 Z"
    return (f'<g transform="translate(6 0)"><path d="{stem}" fill="{A}"/>'
            f'<path d="{stem}" fill="#000" fill-opacity="0.22"/>'
            f'<path d="{bowl}" fill="{A}"/>'
            f'<path d="M60 40 L100 80 H60 Z" fill="#fff" fill-opacity="0.25"/>'
            f'<path d="M60 168 H100 V200 Z" fill="#000" fill-opacity="0.18"/></g>')


def concept_e():
    cx, cy, ri, ro = 128, 236, 84, 196
    parts = []
    for a0, a1, op in [(-150, -104, 0.45), (-101, -79, 1.0), (-76, -30, 0.45)]:
        def pt(r, a):
            return (cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
        p0, p1, p2, p3 = pt(ro, a0), pt(ro, a1), pt(ri, a1), pt(ri, a0)
        parts.append(f'<path d="M{P(*p0)} A{ro} {ro} 0 0 1 {P(*p1)} L{P(*p2)} '
                     f'A{ri} {ri} 0 0 0 {P(*p3)} Z" fill="{A}" fill-opacity="{op}"/>')
    return "".join(parts)


def rrect(x, y, w, h, r):
    return (f"M{f(x+r)} {f(y)} H{f(x+w-r)} A{r} {r} 0 0 1 {f(x+w)} {f(y+r)} V{f(y+h-r)} "
            f"A{r} {r} 0 0 1 {f(x+w-r)} {f(y+h)} H{f(x+r)} A{r} {r} 0 0 1 {f(x)} {f(y+h-r)} "
            f"V{f(y+r)} A{r} {r} 0 0 1 {f(x+r)} {f(y)} Z")


def dtile(x, y, w, h, r):
    """tile with a fully round right side (the bowl of the P)"""
    R = h / 2
    return (f"M{f(x+r)} {f(y)} H{f(x+w-R)} A{f(R)} {f(R)} 0 0 1 {f(x+w-R)} {f(y+h)} "
            f"H{f(x+r)} A{r} {r} 0 0 1 {f(x)} {f(y+h-r)} V{f(y+r)} A{r} {r} 0 0 1 {f(x+r)} {f(y)} Z")


def concept_f(counter=False):
    g, r = 16, 20
    x0 = 52
    stem = rrect(x0, 36, 68, 184, r)
    bx = x0 + 68 + g
    bowl = dtile(bx, 36, 216 - bx + 8, 124, r)
    hole = ""
    if counter:
        cy = 36 + 62
        hole = f' M{f(bx+40)} {cy} a20 20 0 1 0 40 0 a20 20 0 1 0 -40 0 Z'
    return f'<path fill="{A}" fill-rule="evenodd" d="{stem} {bowl}{hole}"/>'


def concept_t(dot=True, w=60, g=14, bw=88, bh=120, r=18, top=40, h=176):
    """Tiled P: the master + stack layout of a tiling desktop spells a P."""
    total = w + g + bw
    x0 = (256 - total) / 2
    stem = rrect(x0, top, w, h, r)
    bx = x0 + w + g
    bowl = dtile(bx, top, bw, bh, r)
    out = f'<path fill="{A}" d="{stem} {bowl}"/>'
    if dot:
        dr = (h - bh - g) / 2
        out += f'<circle cx="{f(bx + dr)}" cy="{f(top + h - dr)}" r="{f(dr)}" fill="{A}"/>'
    return out


def squircle(cx, cy, a, n=5.0, steps=160):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, sn = math.cos(t), math.sin(t)
        x = cx + a * math.copysign(abs(c) ** (2 / n), c)
        y = cy + a * math.copysign(abs(sn) ** (2 / n), sn)
        pts.append(f"{f(x)} {f(y)}")
    return "M" + " L".join(pts) + " Z"


def tile(x, y, w, h, tl, tr, br, bl):
    return (f"M{f(x+tl)} {f(y)} H{f(x+w-tr)} A{tr} {tr} 0 0 1 {f(x+w)} {f(y+tr)} V{f(y+h-br)} "
            f"A{br} {br} 0 0 1 {f(x+w-br)} {f(y+h)} H{f(x+bl)} A{bl} {bl} 0 0 1 {f(x)} {f(y+h-bl)} "
            f"V{f(y+tl)} A{tl} {tl} 0 0 1 {f(x+tl)} {f(y)} Z")


def concept_s(ghost=0.0, g=16, lw=80, th=124, rin=10, rbowl=52):
    a = 108
    x0, y0, x1, y1 = 128 - a, 128 - a, 128 + a, 128 + a
    big = 0
    stem = tile(x0, y0, lw, 2 * a, big, rin, rin, big)
    bx = x0 + lw + g
    bowl = tile(bx, y0, x1 - bx, th, rin, big, rbowl, rin)
    out = (f'<defs><clipPath id="sq"><path d="{squircle(128, 128, a)}"/></clipPath></defs>'
           f'<g clip-path="url(#sq)"><path fill="{A}" d="{stem} {bowl}"/>')
    if ghost:
        out += (f'<path fill="{A}" fill-opacity="{ghost}" d="{tile(bx, y0 + th + g, x1 - bx, 2 * a - th - g, rin, rin, big, rin)}"/>')
    return out + "</g>"


def concept_g():
    cx, cy, R, rr = 140, 104, 68, 34
    ring = (f"M{cx-R} {cy} a{R} {R} 0 1 0 {2*R} 0 a{R} {R} 0 1 0 {-2*R} 0 Z "
            f"M{cx-rr} {cy} a{rr} {rr} 0 1 0 {2*rr} 0 a{rr} {rr} 0 1 0 {-2*rr} 0 Z")
    sx, sw = 58, 34
    stem = rrect(sx, 36, sw, 186, sw / 2)
    gap = rrect(sx - 10, 26, sw + 20, 206, sw / 2 + 10)
    return (f'<defs><mask id="m"><rect width="256" height="256" fill="#fff"/><path d="{gap}" fill="#000"/></mask></defs>'
            f'<path fill="{A}" fill-rule="evenodd" mask="url(#m)" d="{ring}"/><path fill="{A}" d="{stem}"/>')


CONCEPTS = {
    "1-p-prime": (concept_a, "A: P-prime monogram"),
    "2-prime-disc": (concept_b, "B: the prime symbol in a disc"),
    "3-first-light": (concept_c, "C: first light (Prime = the first hour)"),
    "4-orbit-p": (concept_g, "D: orbit P (ring + stem)"),
    "5-bar-and-bowl": (lambda: concept_t(False), "E: bar + bowl"),
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        if old.endswith(".svg"):
            os.remove(os.path.join(OUT, old))
    for k, (fn, note) in CONCEPTS.items():
        with open(os.path.join(OUT, k + ".svg"), "w") as fh:
            fh.write(svg(fn(), note))
        print(k)
