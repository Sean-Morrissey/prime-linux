#!/usr/bin/env python3
"""Build the Prime Linux brand files (original artwork, CC0).

The emblem — "Split tile": one rounded tile, split the way a tiling desktop
splits the screen (one tall window, one beside it). The split spells a P.
Every curve is an exact circular arc, so the SVG renders identically in
librsvg (bar, GTK), Qt (SDDM) and ImageMagick, and stays tiny.

#f87171 is the accent token: prime-theme replaces it with the user's accent.

    layer/branding/src/make-brand.py [--fonts DIR]

--fonts must hold InterDisplay-SemiBold.ttf + InterDisplay-Regular.ttf (Inter
is OFL; only the wordmark's outlines are written out, no font is shipped).
Without it the wordmark files are left as they are.
"""
import argparse, glob, os, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
BR = os.path.normpath(os.path.join(HERE, ".."))
ACCENT = "#f87171"
INK_DARK = "#f4f4f6"     # text on dark
INK_LIGHT = "#17171c"    # text on light


def f(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def tile(x, y, w, h, tl, tr, br, bl):
    """rectangle with an independent radius per corner (exact arcs)"""
    p = [f"M{f(x + tl)} {f(y)}", f"H{f(x + w - tr)}"]
    if tr: p.append(f"A{f(tr)} {f(tr)} 0 0 1 {f(x + w)} {f(y + tr)}")
    p.append(f"V{f(y + h - br)}")
    if br: p.append(f"A{f(br)} {f(br)} 0 0 1 {f(x + w - br)} {f(y + h)}")
    p.append(f"H{f(x + bl)}")
    if bl: p.append(f"A{f(bl)} {f(bl)} 0 0 1 {f(x)} {f(y + h - bl)}")
    p.append(f"V{f(y + tl)}")
    if tl: p.append(f"A{f(tl)} {f(tl)} 0 0 1 {f(x + tl)} {f(y)}")
    return " ".join(p) + " Z"


# Geometry on a 256 grid. `small` is the optical size for 16–24 px: a wider
# split and softer inner corners so the gap survives the pixel grid.
def emblem_paths(small=False):
    s = 216                     # tile size
    x0 = y0 = (256 - s) / 2     # 20
    R = 40                      # outer corners (lw >= R + rin, th >= R + rb)
    g = 26 if small else 18     # the split
    lw = 66 if small else 68    # stem width
    th = 126                    # bowl height
    rin = 12                    # inner corners
    rb = 72                     # the bowl: one long sweep back to the split
    stem = tile(x0, y0, lw, s, R, rin, rin, R)
    bx = x0 + lw + g
    bowl = tile(bx, y0, s - lw - g, th, rin, R, rb, rin)
    return stem, bowl


def mark_svg(fill=ACCENT, small=False, note=""):
    stem, bowl = emblem_paths(small)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">\n'
            f'  <!-- Prime Linux emblem "Split tile"{note}. Original artwork, CC0.\n'
            f'       prime-theme recolours #f87171 to the accent. -->\n'
            f'  <path fill="{fill}" d="{stem}"/>\n'
            f'  <path fill="{fill}" d="{bowl}"/>\n'
            f'</svg>\n')


# ── wordmark: outlines from Inter Display with its own kerning ───────────────
def _kern_table(font):
    """{(left, right): xAdvance} from GPOS PairPos (formats 1 + 2)."""
    pairs = {}
    if "GPOS" not in font:
        return pairs
    gpos = font["GPOS"].table
    for lookup in gpos.LookupList.Lookup:
        subs = lookup.SubTable
        if lookup.LookupType == 9:
            subs = [s.ExtSubTable for s in subs]
        for st in subs:
            if getattr(st, "LookupType", 2) != 2 and lookup.LookupType != 9:
                continue
            if not hasattr(st, "Format") or not hasattr(st, "Coverage"):
                continue
            cov = st.Coverage.glyphs
            if st.Format == 1:
                for i, first in enumerate(cov):
                    for pvr in st.PairSet[i].PairValueRecord:
                        v = getattr(pvr.Value1, "XAdvance", 0) or 0
                        pairs.setdefault((first, pvr.SecondGlyph), v)
            elif st.Format == 2:
                c1, c2 = st.ClassDef1.classDefs, st.ClassDef2.classDefs
                for first in cov:
                    k1 = c1.get(first, 0)
                    rec = st.Class1Record[k1]
                    for second, k2 in list(c2.items()):
                        v = getattr(rec.Class2Record[k2].Value1, "XAdvance", 0) or 0
                        if v:
                            pairs.setdefault((first, second), v)
    return pairs


def text_path(fontfile, text, size, x, baseline, tracking=0.0):
    from fontTools.ttLib import TTFont
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen
    font = TTFont(fontfile)
    upm = font["head"].unitsPerEm
    sc = size / upm
    cmap = font.getBestCmap()
    gs = font.getGlyphSet()
    kern = _kern_table(font)
    hmtx = font["hmtx"]
    out, pen_x, prev = [], x, None
    for ch in text:
        gn = cmap[ord(ch)]
        if prev is not None:
            pen_x += kern.get((prev, gn), 0) * sc
        sp = SVGPathPen(gs)
        tp = TransformPen(sp, (sc, 0, 0, -sc, pen_x, baseline))
        gs[gn].draw(tp)
        d = sp.getCommands()
        if d:
            out.append(d)
        pen_x += hmtx[gn][0] * sc + tracking * size
        prev = gn
    cap = font["OS/2"].sCapHeight * sc
    return " ".join(out), pen_x - tracking * size, cap


def round_path(d):
    import re
    return re.sub(r"-?\d+\.\d+", lambda m: f(float(m.group())), d)


def wordmark(fonts, ink, with_mark, accent=ACCENT):
    semi = os.path.join(fonts, "InterDisplay-SemiBold.ttf")
    reg = os.path.join(fonts, "InterDisplay-Regular.ttf")
    size = 100.0
    # Inter cap height ≈ 0.727 em; the mark is 1.34× cap height, centred on the caps
    _, _, cap = text_path(semi, "P", size, 0, 0)
    mh = cap * 1.34
    pad = 0
    mx = pad
    gap = mh * 0.36 if with_mark else 0
    tx = (mx + mh + gap) if with_mark else pad
    baseline = mh / 2 + cap / 2           # caps centred on the mark
    d1, x1, _ = text_path(semi, "Prime", size, tx, baseline, tracking=-0.012)
    space = size * 0.26
    d2, x2, _ = text_path(reg, "Linux", size, x1 + space, baseline, tracking=-0.004)
    w, h = x2 + pad, mh
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {f(w)} {f(h)}" width="{f(w)}" height="{f(h)}">',
             '  <!-- Prime Linux wordmark. Original artwork, CC0; letterforms are Inter Display outlines (OFL). -->']
    if with_mark:
        stem, bowl = emblem_paths()
        k = mh / 216
        parts.append(f'  <g transform="translate({f(mx - 20 * k)} {f(-20 * k)}) scale({f(k)})" fill="{accent}">'
                     f'<path d="{stem}"/><path d="{bowl}"/></g>')
    parts.append(f'  <path fill="{ink}" d="{round_path(d1)}"/>')
    parts.append(f'  <path fill="{ink}" fill-opacity="0.62" d="{round_path(d2)}"/>')
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def png(svg, out, w, h=None):
    cmd = ["rsvg-convert", "-w", str(w)] + (["-h", str(h)] if h else []) + [svg, "-o", out]
    subprocess.run(cmd, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fonts", help="folder with InterDisplay-SemiBold.ttf / -Regular.ttf")
    a = ap.parse_args()
    files = {
        "mark.svg": mark_svg(),
        "mark-small.svg": mark_svg(small=True, note=" — optical size for 16–24 px"),
        "mark-symbolic.svg": mark_svg("#bebebe", small=True, note=" — symbolic (single colour, GTK recolours #bebebe)"),
        "mark-white.svg": mark_svg("#ffffff", note=" — white, for boot and login screens"),
    }
    for n, s in files.items():
        with open(os.path.join(BR, n), "w") as fh:
            fh.write(s)
    if a.fonts:
        for n, ink, m in [("wordmark-dark.svg", INK_DARK, False), ("wordmark-light.svg", INK_LIGHT, False),
                          ("lockup-dark.svg", INK_DARK, True), ("lockup-light.svg", INK_LIGHT, True)]:
            with open(os.path.join(BR, n), "w") as fh:
                fh.write(wordmark(a.fonts, ink, m))
        with open(os.path.join(BR, "lockup-white.svg"), "w") as fh:
            fh.write(wordmark(a.fonts, "#ffffff", True, accent="#ffffff"))
    os.makedirs(os.path.join(BR, "png"), exist_ok=True)
    for px in (16, 24, 32, 48, 64, 128, 256, 512):
        src = "mark-small.svg" if px <= 24 else "mark.svg"
        png(os.path.join(BR, src), os.path.join(BR, "png", f"mark-{px}.png"), px, px)
    png(os.path.join(BR, "mark-white.svg"), os.path.join(BR, "png", "mark-white-256.png"), 256, 256)
    for n in ("lockup-dark", "lockup-light", "lockup-white"):
        if os.path.exists(os.path.join(BR, n + ".svg")):
            png(os.path.join(BR, n + ".svg"), os.path.join(BR, "png", n + ".png"), 1200)
    print("brand files written to", BR)


if __name__ == "__main__":
    main()
