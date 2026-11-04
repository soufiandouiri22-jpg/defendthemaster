"""Draws the pictures of Corvin's shots (src/client/GunEffects.luau) as PNGs in Art/UI/:

- gun_flash.png: a muzzle flash seen from the side: a white-hot core, six tapered tongues of flame of different
  lengths round it, the longest forward (up), in a soft orange halo.
- gun_glow.png: a soft round glow, white, to be tinted.
- gun_streak.png: a tracer's streak for a Beam, lying along the image's width as a Beam lays its texture: a bright
  thin core in a soft glow, white.
- gun_spark.png: one spark, a short bright line with soft ends, white, flown along its way.
Drawn at twice the size and scaled down, as Tools/ui_textures.py does. Upload them through Studio (the Studio MCP's
upload_image, from a local http.server on Art/UI) and put their ids in src/shared/Assets.luau.

    python3 Tools/gun_textures.py
"""

from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "Art" / "UI"
SS = 2


def grid(w, h):
    ys, xs = np.mgrid[0 : h * SS, 0 : w * SS].astype(np.float32)
    return (xs + 0.5) / SS - w / 2, (ys + 0.5) / SS - h / 2


def smooth(a, b, t):
    t = np.clip((t - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def save(rgb, alpha, name):
    h, w = alpha.shape[0] // SS, alpha.shape[1] // SS
    rgba = np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)[..., None]])
    img = Image.fromarray((rgba * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / name)
    print("wrote", OUT / name, img.size)


def flash():
    n = 256
    x, y = grid(n, n)
    edge = n / 2
    r = np.hypot(x, y) / edge
    angle = np.arctan2(y, x)
    # The tongues: (direction in degrees, 0 forward; length as a share of the radius; width at the root).
    tongues = [(0, 0.98, 0.62), (36, 0.66, 0.5), (-40, 0.7, 0.5), (92, 0.46, 0.44), (-96, 0.44, 0.44), (180, 0.34, 0.5)]
    heat = np.zeros_like(r)
    for direction, length, width in tongues:
        # Forward is up in the picture, as a particle flown along its way (VelocityParallel) lays its height along it.
        d = np.radians(direction - 90)
        along = (x * np.cos(d) + y * np.sin(d)) / edge
        across = np.abs(-x * np.sin(d) + y * np.cos(d)) / edge
        t = np.clip(along / length, 0, 1)
        # Wide at the root, rounded, to a point at its tip, brightest along its middle.
        half = width * 0.5 * np.sqrt(1 - t) * (1 - t) ** 0.6 + 0.004
        inside = np.clip(1 - across / half, 0, 1) * (along > -0.1) * (along < length)
        heat = np.maximum(heat, inside**0.6 * (1 - t) ** 0.45)
    core = np.clip(1 - r / 0.3, 0, 1) ** 1.2
    halo = np.exp(-((r / 0.5) ** 2)) * 0.7
    heat = np.clip(np.maximum(heat, core), 0, 1)
    alpha = np.clip(np.maximum(heat, halo), 0, 1)
    # White where hottest, through yellow to orange at the edges and in the halo.
    white = np.array([1.0, 0.98, 0.9])
    yellow = np.array([1.0, 0.82, 0.38])
    orange = np.array([1.0, 0.45, 0.12])
    hot = smooth(0.55, 0.95, heat)[..., None]
    warm = smooth(0.15, 0.55, heat)[..., None]
    rgb = orange * (1 - warm) + yellow * warm
    rgb = rgb * (1 - hot) + white * hot
    save(rgb, alpha, "gun_flash.png")


def glow():
    n = 128
    x, y = grid(n, n)
    r = np.hypot(x, y) / (n / 2)
    alpha = np.exp(-((r / 0.45) ** 2)) * np.clip(1 - r, 0, 1) ** 0.5
    save(np.ones(r.shape + (3,)), alpha, "gun_glow.png")


def streak():
    w, h = 256, 64
    x, y = grid(w, h)
    across = np.abs(y) / (h / 2)
    alpha = np.maximum(np.exp(-((across / 0.12) ** 2)), 0.55 * np.exp(-((across / 0.45) ** 2)))
    save(np.ones(across.shape + (3,)), alpha, "gun_streak.png")


def spark():
    w, h = 128, 32
    x, y = grid(w, h)
    along = np.abs(x) / (w / 2)
    across = np.abs(y) / (h / 2)
    line = np.exp(-((across / (0.22 * (1 - along) + 0.05)) ** 2)) * (1 - smooth(0.5, 1, along))
    alpha = np.maximum(line, 0.35 * np.exp(-((across / 0.6) ** 2)) * (1 - smooth(0.2, 1, along)))
    save(np.ones(along.shape + (3,)), alpha, "gun_spark.png")


if __name__ == "__main__":
    flash()
    glow()
    streak()
    spark()
