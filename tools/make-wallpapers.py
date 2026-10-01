#!/usr/bin/env python3
"""Generate Prime Linux's wallpaper set (original art, CC0 — safe to ship).

Each wallpaper is a dark field with large soft light blooms and fine flowing
ribbons, so the frosted-glass bar and windows have colour to blur. Deterministic
(seeded), so re-running reproduces the same files.

    tools/make-wallpapers.py [--out layer/wallpapers] [--size 3840x2160]
"""
import argparse, math, os
import numpy as np
from PIL import Image

SETS = {
    # name: (base rgb, [(x, y, radius, rgb, strength)...], ribbon rgb)
    "prime-ember":    ((10, 8, 12),  [(0.78, 0.30, 0.55, (248, 90, 80), 1.0), (0.18, 0.85, 0.45, (190, 40, 70), 0.8)], (255, 140, 120)),
    "prime-tide":     ((6, 10, 18),  [(0.25, 0.25, 0.60, (60, 140, 250), 1.0), (0.85, 0.80, 0.50, (40, 200, 220), 0.7)], (140, 200, 255)),
    "prime-aurora":   ((5, 12, 12),  [(0.70, 0.20, 0.55, (40, 210, 150), 0.9), (0.20, 0.70, 0.55, (60, 120, 230), 0.7)], (140, 255, 200)),
    "prime-dusk":     ((10, 7, 16),  [(0.30, 0.30, 0.55, (170, 100, 250), 1.0), (0.80, 0.75, 0.50, (240, 90, 160), 0.8)], (220, 170, 255)),
    "prime-dune":     ((14, 10, 6),  [(0.65, 0.35, 0.60, (250, 170, 50), 0.9), (0.15, 0.80, 0.45, (230, 90, 40), 0.7)], (255, 210, 140)),
    "prime-graphite": ((10, 10, 12), [(0.50, 0.35, 0.70, (150, 150, 165), 0.6), (0.85, 0.85, 0.40, (90, 95, 110), 0.5)], (210, 210, 225)),
}


def render(name, w, h, seed):
    base, blooms, ribbon = SETS[name]
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    nx, ny = xx / w, yy / h * (h / w)
    img = np.zeros((h, w, 3), np.float32) + np.array(base, np.float32)
    for (cx, cy, r, col, s) in blooms:
        d2 = (nx - cx) ** 2 + (ny - cy * (h / w)) ** 2
        img += np.exp(-d2 / (2 * (r * 0.45) ** 2))[..., None] * np.array(col, np.float32) * 0.55 * s
    # flowing ribbons: a few phase-shifted sine bands, thin and glowing
    for k in range(5):
        ph, fr, amp = rng.uniform(0, 2 * math.pi), rng.uniform(1.2, 2.6), rng.uniform(0.05, 0.12)
        off = 0.25 + 0.1 * k + rng.uniform(-0.04, 0.04)
        line = off + amp * np.sin(nx * fr * math.pi + ph) + 0.03 * np.sin(nx * 7.3 + ph * 2)
        d = np.abs(ny / (h / w) - line)
        img += np.exp(-(d / 0.0025) ** 2)[..., None] * np.array(ribbon, np.float32) * 0.22
        img += np.exp(-(d / 0.02) ** 2)[..., None] * np.array(ribbon, np.float32) * 0.06
    # vignette + fine grain (stops banding on 8-bit panels)
    vig = 1 - 0.55 * (((nx - 0.5) ** 2 + (ny / (h / w) - 0.5) ** 2) ** 0.9)
    img *= vig[..., None]
    img += rng.normal(0, 1.6, img.shape)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "layer", "wallpapers"))
    ap.add_argument("--size", default="3840x2160")
    a = ap.parse_args()
    w, h = map(int, a.size.split("x"))
    os.makedirs(a.out, exist_ok=True)
    for i, name in enumerate(SETS):
        p = os.path.join(a.out, f"{name}.jpg")
        render(name, w, h, 1000 + i).save(p, quality=92, subsampling=0, optimize=True)
        print(p, os.path.getsize(p) // 1024, "KiB")


if __name__ == "__main__":
    main()
