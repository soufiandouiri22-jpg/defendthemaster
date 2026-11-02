"""Draws the portals' vortex (the turquoise swirl inside each portal ring, PortalView) as PNGs in Art/VFX/: the filled
swirl, its arms winding in to a white heart through cyan and teal; the bright arms alone, turned against it; its soft
glow; and the bright rim along the stones. The game lays them on both faces of the ring's opening and spins them.
Upload them through Studio (the Studio MCP's upload_image, from a local http.server on Art/VFX) and put their ids in
src/shared/Assets.luau.

    python3 Tools/portal_textures.py
"""

import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Art/VFX"
SIZE = 512

# From the heart out: white, pale cyan, turquoise, teal, deep sea blue.
STOPS = [(0.0, (245, 255, 255)), (0.15, (170, 250, 255)), (0.4, (60, 220, 230)), (0.7, (20, 150, 190)), (1.0, (10, 70, 120))]


def ramp(t):
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        inside = (t >= t0) & (t <= t1)
        f = ((t - t0) / (t1 - t0))[..., None]
        out = np.where(inside[..., None], np.array(c0) * (1 - f) + np.array(c1) * f, out)
    return out


def polar():
    ys, xs = np.mgrid[0:SIZE, 0:SIZE].astype(np.float64) + 0.5
    x, y = (xs - SIZE / 2) / (SIZE / 2), (ys - SIZE / 2) / (SIZE / 2)
    return np.hypot(x, y), np.arctan2(y, x)


def noise(rng, cells):
    small = Image.fromarray((rng.random((cells, cells)) * 255).astype(np.uint8))
    return np.asarray(small.resize((SIZE, SIZE), Image.BICUBIC), dtype=np.float64) / 255


def save(rgb, alpha, name):
    OUT.mkdir(parents=True, exist_ok=True)
    data = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 1) * 255]).astype(np.uint8)
    Image.fromarray(data).save(OUT / name)
    print(f"Wrote {(OUT / name).relative_to(ROOT)}")


def arms(r, angle, warp, turns, sharp):
    """Four arms on a logarithmic spiral, sharp on their leading edge and trailing off behind."""
    phase = (4 * (angle + turns * np.log(np.maximum(r, 1e-3)) + warp) / (2 * math.pi)) % 1
    return np.exp(-((phase - 0.3) / sharp) ** 2) + 0.5 * np.exp(-((phase - 0.6) / (sharp * 1.8)) ** 2)


def swirl():
    """The filled vortex: the whole opening in deep teal, lighter arms winding into a white heart."""
    r, angle = polar()
    rng = np.random.default_rng(5)
    warp = (noise(rng, 8) - 0.5) * 0.8
    band = np.clip(arms(r, angle, warp, 2.2, 0.14), 0, 1)
    heart = np.exp(-((r / 0.22) ** 2))
    edge = np.clip((1 - r) / 0.03, 0, 1)
    alpha = np.clip(0.88 + band * 0.12 + heart, 0, 1) * edge
    rgb = ramp(r * 0.95 + 0.12 - band * 0.35 - heart * 0.3)
    save(rgb, alpha, "portal_swirl.png")


def streaks():
    """The bright arms alone, thin and torn, to turn against the swirl."""
    r, angle = polar()
    rng = np.random.default_rng(9)
    warp = (noise(rng, 10) - 0.5) * 1.2 + (noise(rng, 30) - 0.5) * 0.4
    band = np.clip(arms(r, angle, warp, 1.6, 0.05), 0, 1)
    grain = noise(rng, 40)
    fade = np.clip(1 - r**2, 0, 1) ** 0.7 * np.clip(r / 0.15, 0, 1)
    alpha = band * (0.6 + 0.5 * grain) * fade
    rgb = ramp(0.08 + r * 0.35)
    save(rgb, alpha, "portal_streaks.png")


def glow():
    r, _ = polar()
    alpha = (np.exp(-((r / 0.4) ** 2)) * 0.9 + np.exp(-((r / 0.8) ** 2)) * 0.4) * np.clip((1 - r) * 6, 0, 1)
    save(ramp(0.05 + r * 0.5), alpha, "portal_glow.png")


def rim():
    """A bright ring along the opening's edge, soft inwards, so the vortex glows against the stones."""
    r, angle = polar()
    rng = np.random.default_rng(13)
    wobble = (noise(rng, 12) - 0.5) * 0.04
    line = np.exp(-(((r - 0.93 - wobble) / 0.035) ** 2))
    inner = np.exp(-(((r - 0.85) / 0.1) ** 2)) * 0.45 * (r < 0.95)
    alpha = np.clip(line + inner, 0, 1) * (r < 1)
    rgb = ramp(0.15 + (1 - line) * 0.3)
    save(rgb, alpha, "portal_rim.png")


if __name__ == "__main__":
    swirl()
    streaks()
    glow()
    rim()
