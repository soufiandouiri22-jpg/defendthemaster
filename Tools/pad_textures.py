"""Draws the spawn pads' textures (design 03) as PNGs in Art/UI/: the rune circle that glows on every pad and the soft
ring that sweeps out when a hero comes back.

Both are white with alpha, so the game tints them in the team's colour. Drawn with the distance-field helpers of
ui_textures.py at four times the size, with a blurred copy under the lines for their glow. Upload them through Studio
(the Studio MCP's upload_image, from a local http.server on Art/UI) and put their ids in src/shared/Assets.luau.

    python3 Tools/pad_textures.py
"""

import math
import random

import numpy as np
from PIL import Image, ImageFilter

from ui_textures import SS, band, grid, save, white

SIZE = 512


def segment(xs, ys, a, b):
    """Distance from every pixel to the segment a-b."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    t = np.clip(((xs - ax) * dx + (ys - ay) * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(xs - (ax + t * dx), ys - (ay + t * dy))


def glow(alpha, radius, strength):
    """`alpha` with a soft halo of `radius` output pixels under it."""
    img = Image.fromarray((alpha * 255).astype(np.uint8))
    halo = np.asarray(img.filter(ImageFilter.GaussianBlur(radius * SS)), dtype=np.float32) / 255
    return np.clip(np.maximum(alpha, halo * strength), 0, 1)


def rune_circle():
    xs, ys = grid(SIZE, SIZE)
    c = SIZE / 2
    x, y = xs - c, ys - c
    r = np.hypot(x, y) / c
    angle = np.arctan2(y, x)
    px = 1 / c  # one output pixel in radius units
    lines = np.zeros_like(r)

    def ring(radius, width):
        return band((r - radius) / px, width)

    for radius, width in ((0.95, 7), (0.87, 3), (0.62, 2.5), (0.40, 4), (0.13, 3)):
        lines = np.maximum(lines, ring(radius, width))
    # Fine ticks between the two outer rings.
    ticks = band(((angle / (2 * math.pi) * 72) % 1 - 0.5) * (2 * math.pi * 0.91 / 72) / px, 2.5)
    lines = np.maximum(lines, ticks * ((r > 0.875) & (r < 0.945)))
    # An eight-pointed star of two squares inside the inner rune ring, and the cross through the heart.
    for turn in (0, math.pi / 4):
        corners = [(math.cos(turn + k * math.pi / 2) * 0.60 * c, math.sin(turn + k * math.pi / 2) * 0.60 * c) for k in range(4)]
        for k in range(4):
            lines = np.maximum(lines, band(segment(x, y, corners[k], corners[(k + 1) % 4]), 2.5))
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        inner = (math.cos(a) * 0.13 * c, math.sin(a) * 0.13 * c)
        outer = (math.cos(a) * 0.40 * c, math.sin(a) * 0.40 * c)
        lines = np.maximum(lines, band(segment(x, y, inner, outer), 4))
    # Twelve runes of our own between the star and the outer rings: each a few strokes on a small grid.
    rng = random.Random(7)
    for k in range(12):
        a = k * math.pi / 6 + math.pi / 12
        cx, cy = math.cos(a) * 0.745 * c, math.sin(a) * 0.745 * c
        up = (math.cos(a), math.sin(a))
        side = (-up[1], up[0])
        s = 0.055 * c
        points = [(i, j) for i in (-1, 0, 1) for j in (-1, 0, 1)]
        for _ in range(3):
            p, q = rng.sample(points, 2)
            pa = (cx + (p[0] * side[0] + p[1] * up[0]) * s, cy + (p[0] * side[1] + p[1] * up[1]) * s)
            pb = (cx + (q[0] * side[0] + q[1] * up[0]) * s, cy + (q[0] * side[1] + q[1] * up[1]) * s)
            lines = np.maximum(lines, band(segment(x, y, pa, pb), 3.5))
    # A faint wash over the disc so the whole circle glows a little.
    wash = np.clip(1 - r, 0, 1) ** 1.5 * 0.18 * (r < 0.95)
    alpha = np.maximum(glow(lines, 6, 0.75), wash)
    save(white(alpha), "pad_runes.png")


def sweep_ring():
    xs, ys = grid(SIZE, SIZE)
    c = SIZE / 2
    r = np.hypot(xs - c, ys - c) / c
    alpha = np.exp(-(((r - 0.86) / 0.05) ** 2)) + 0.35 * np.exp(-(((r - 0.80) / 0.12) ** 2))
    alpha *= r < 0.99
    save(white(np.clip(alpha, 0, 1)), "pad_ring.png")


if __name__ == "__main__":
    rune_circle()
    sweep_ring()
