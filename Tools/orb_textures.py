"""Draws Mavorak's orb (the purple vortex in his hand on his portrait) as PNGs in Art/VFX/: the swirl, its arms
winding in to a white heart through pink and violet, and the soft glow round it. The game turns them towards the
camera and spins them (HeroControls' projectileModel). Upload them through Studio (the Studio MCP's upload_image, from
a local http.server on Art/VFX) and put their ids in src/shared/Assets.luau.

    python3 Tools/orb_textures.py
"""

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Art/VFX"
SIZE = 512

# From the heart out: white, pink, violet, deep purple.
STOPS = [(0.0, (255, 245, 255)), (0.18, (255, 170, 250)), (0.45, (190, 90, 255)), (0.75, (120, 40, 220)), (1.0, (60, 10, 130))]


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


def save(rgb, alpha, name):
    OUT.mkdir(parents=True, exist_ok=True)
    data = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 1) * 255]).astype(np.uint8)
    Image.fromarray(data).save(OUT / name)
    print(f"Wrote {(OUT / name).relative_to(ROOT)}")


def swirl():
    r, angle = polar()
    # Three arms on a logarithmic spiral, sharp on their leading edge and trailing off behind.
    phase = (3 * (angle + 2.6 * np.log(np.maximum(r, 1e-3))) / (2 * math.pi)) % 1
    arms = np.exp(-((phase - 0.25) / 0.16) ** 2) + 0.55 * np.exp(-((phase - 0.62) / 0.1) ** 2)
    fade = np.clip(1 - r, 0, 1) ** 0.8
    heart = np.exp(-((r / 0.2) ** 2))
    alpha = np.clip(arms * fade * 1.1 + heart, 0, 1) * (r < 1)
    rgb = ramp(r * 1.05 - heart * 0.2 + (1 - np.clip(arms, 0, 1)) * 0.15)
    save(rgb, alpha, "orb_swirl.png")


def vortex():
    """The darker vortex (owner 2026-10-30: less sweet, less light, no ball): a near-black heart of smoke that thin
    violet arms with magenta edges wind into."""
    r, angle = polar()
    rng = np.random.default_rng(3)

    def noise(cells):
        small = Image.fromarray((rng.random((cells, cells)) * 255).astype(np.uint8))
        return np.asarray(small.resize((SIZE, SIZE), Image.BICUBIC), dtype=np.float64) / 255

    # Three wide arms, few turns, their course torn by noise so they read as raging energy.
    warp = (noise(8) - 0.5) * 1.4 + (noise(24) - 0.5) * 0.5
    phase = (3 * (angle + 1.9 * np.log(np.maximum(r, 1e-3)) + warp) / (2 * math.pi)) % 1
    edge = np.exp(-((phase - 0.3) / 0.045) ** 2)
    body = np.exp(-((phase - 0.45) / 0.15) ** 2)
    grain = noise(48)
    fade = np.clip(1 - r**2, 0, 1) ** 1.5
    dark = np.exp(-((r / 0.5) ** 2)) * 0.95
    arms = np.clip((edge * 1.3 + body * 0.6) * (0.55 + 0.7 * grain), 0, 1) * fade
    alpha = np.clip(np.maximum(dark, arms), 0, 1) * fade
    violet = np.array((150, 40, 255)) * body[..., None] + np.array((255, 90, 240)) * edge[..., None]
    shade = np.array((18, 4, 30))
    rgb = shade * (1 - arms[..., None]) + np.clip(violet, 0, 255) * arms[..., None]
    save(rgb, alpha, "orb_vortex.png")


def wisps():
    """Crackling arcs of energy round the vortex: a few jagged strokes on rings, magenta at their hearts."""
    r, angle = polar()
    rng = np.random.default_rng(11)
    alpha = np.zeros_like(r)
    for _ in range(7):
        radius = rng.uniform(0.45, 0.85)
        start = rng.uniform(-math.pi, math.pi)
        length = rng.uniform(0.6, 1.3)
        a = (angle - start) % (2 * math.pi)
        inside = a < length
        jag = radius + 0.035 * np.sin(a * rng.uniform(18, 30)) + 0.02 * np.sin(a * rng.uniform(45, 70))
        line = np.exp(-(((r - jag) / 0.012) ** 2)) * inside * np.sin(np.clip(a / length, 0, 1) * math.pi)
        alpha = np.maximum(alpha, line)
    halo = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5)), dtype=np.float64) / 255
    rgb = np.array((255, 150, 255)) * alpha[..., None] + np.array((140, 40, 255)) * (1 - alpha[..., None])
    save(rgb, np.clip(np.maximum(alpha, halo * 1.6), 0, 1), "orb_wisps.png")


def glow():
    r, _ = polar()
    alpha = (np.exp(-((r / 0.45) ** 2)) * 0.85 + np.exp(-((r / 0.85) ** 2)) * 0.35) * np.clip((1 - r) * 6, 0, 1)
    save(ramp(0.3 + r * 0.6), alpha, "orb_glow.png")


if __name__ == "__main__":
    swirl()
    vortex()
    wisps()
    glow()
