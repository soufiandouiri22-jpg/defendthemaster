"""Draws the ability indicators (design 06) and the crosshairs (design 09) as PNGs in Art/UI/.

The indicators are white with soft alpha gradients and a fine outline, so the game tints them (gold, white, red) with
ImageColor3; the crosshairs carry their colours. Every shape is drawn from a distance field at four times the size and
scaled down, so the edges stay smooth. Upload the PNGs through Studio (the Studio MCP's upload_image, from a local
http.server on Art/UI) and put their ids in src/shared/Assets.luau.

    python3 Tools/ui_textures.py
"""

from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "Art" / "UI"
SS = 4


def grid(w, h):
    """Pixel centres in units where the image is w x h (y down)."""
    ys, xs = np.mgrid[0 : h * SS, 0 : w * SS].astype(np.float32)
    return (xs + 0.5) / SS, (ys + 0.5) / SS


def coverage(d, soft=0.75):
    """Anti-aliased inside (distance d < 0 inside), in output pixels."""
    return np.clip(0.5 - d / soft, 0, 1)


def band(d, width):
    """A line of `width` pixels along d = 0."""
    return coverage(np.abs(d) - width / 2)


def save(rgba, name):
    h, w = rgba.shape[:2]
    img = Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA")
    img = img.resize((w // SS, h // SS), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / name)
    print("wrote", OUT / name, img.size)


def white(alpha):
    rgba = np.ones(alpha.shape + (4,), np.float32)
    rgba[..., 3] = alpha
    return rgba


def disc():
    """A disc: a faint centre growing to the rim, a fine bright outline and a soft glow just inside it."""
    n = 512
    x, y = grid(n, n)
    r = np.hypot(x - n / 2, y - n / 2)
    edge = n / 2 - 6
    d = r - edge
    inside = coverage(d)
    t = np.clip(r / edge, 0, 1)
    fill = (0.22 + 0.25 * t**2.2) * inside
    glow = np.exp(-np.maximum(-d, 0) / 16) * 0.45 * inside
    line = band(d, 5) * 1.0
    save(white(np.maximum(fill + glow, line)), "indicator_disc.png")


def ring():
    """The enemy warning: a soft ring with a bright core line."""
    n = 512
    x, y = grid(n, n)
    r = np.hypot(x - n / 2, y - n / 2)
    d = r - (n / 2 - 40)
    soft = np.exp(-(d / 14) ** 2) * 0.55
    line = band(d, 4) * 0.95
    save(white(np.maximum(soft, line)), "indicator_ring.png")


def cone(angle=70):
    """A cone from its apex at the bottom centre, `angle` degrees wide, as tall as its reach: a fill that grows with the
    distance, fine outlines along both sides and the arc, and three faint arcs inside."""
    half = np.radians(angle / 2)
    h = 512
    w = int(np.ceil(2 * np.sin(half) * h)) + 16
    x, y = grid(w, h)
    px, py = x - w / 2, (h - 4) - y
    r = np.hypot(px, py)
    a = np.arctan2(px, py)
    reach = h - 10
    d_arc = r - reach
    side = np.abs(a) - half
    d_side = np.sin(np.minimum(np.abs(side), np.pi / 2)) * r * np.sign(side)
    d = np.maximum(d_arc, d_side)
    inside = coverage(d)
    t = np.clip(r / reach, 0, 1)
    fill = (0.20 + 0.25 * t**1.6) * inside
    glow = np.exp(-np.maximum(-d, 0) / 14) * 0.45 * inside
    line = band(d, 5) * 1.0
    arcs = sum(band(r - reach * k, 2.5) for k in (0.25, 0.5, 0.75)) * 0.4 * inside
    save(white(np.maximum(fill + glow + arcs, line)), "indicator_cone.png")


# The skillshot arrow in two pieces, so its shaft stretches to any length and its head keeps its shape: the shaft is
# SHAFT of the image's width, the head the whole width.
ARROW_W = 256
SHAFT = 0.5


def arrow_shaft():
    """The shaft, pointing up: brightening from its tail to the head, with fine outlines along its sides."""
    w, h = ARROW_W, 512
    x, y = grid(w, h)
    half = w * SHAFT / 2
    d_side = np.abs(x - w / 2) - half
    inside = coverage(d_side)
    t = 1 - y / h
    fill = (0.06 + 0.34 * t**1.3) * inside
    glow = np.exp(-np.maximum(-d_side, 0) / 9) * (0.15 + 0.25 * t) * inside
    core = np.exp(-((x - w / 2) / 14) ** 2) * 0.22 * t * inside
    line = band(d_side, 3.5) * (0.35 + 0.6 * t)
    save(white(np.maximum(fill + glow + core, line)), "indicator_arrow_shaft.png")


def arrow_head():
    """The head, pointing up, its base as wide as the image; the base's outline leaves the shaft's width open."""
    w, h = ARROW_W, 224
    x, y = grid(w, h)
    top, base = 8, h - 2
    k = (w / 2 - 8) / (base - top)
    d_side = (np.abs(x - w / 2) - k * (y - top)) / np.sqrt(1 + k * k)
    d = np.maximum(d_side, y - (base - 4))
    inside = coverage(d)
    fill = 0.42 * inside
    glow = np.exp(-np.maximum(-d, 0) / 10) * 0.4 * inside
    line = band(d, 3.5) * 0.95
    line = np.where((np.abs(x - w / 2) < w * SHAFT / 2 - 2) & (y > base - 12), 0, line)
    save(white(np.maximum(fill + glow, line)), "indicator_arrow_head.png")


def crosshair(name, colour, outline, enemy=False):
    """Four triangles pointing at the centre and a dot (design 09); the enemy one has a thin ring and a hollow centre."""
    n = 128
    x, y = grid(n, n)
    px, py = x - n / 2, y - n / 2
    alpha = np.zeros_like(px)
    shade = np.zeros_like(px)
    for rot in range(4):
        ang = rot * np.pi / 2 + (np.pi / 4 if enemy else 0)
        c, s = np.cos(ang), np.sin(ang)
        u = c * px + s * py
        v = -s * px + c * py
        tip, base, half = 20, 46, 13
        k = half / (base - tip)
        d_side = (np.abs(v) - k * (u - tip)) / np.sqrt(1 + k * k)
        d = np.maximum(d_side, np.maximum(tip - u, u - base))
        a = coverage(d)
        lit = np.clip(0.55 + 0.45 * (1 - (u - tip) / (base - tip)), 0, 1)
        shade = np.where(a > alpha, lit, shade)
        alpha = np.maximum(alpha, a)
        outline_a = coverage(d - 3) * (1 - a)
        alpha = np.maximum(alpha, outline_a * 0.9)
        shade = np.where(outline_a > 0.5, -1, shade)
    r = np.hypot(px, py)
    if enemy:
        hollow = coverage(np.abs(r - 7) - 3)
        ring_line = band(r - 40, 2) * 0.8
        dot = np.maximum(hollow, ring_line)
    else:
        dot = coverage(r - 5)
    shade = np.where(dot > alpha, 1, shade)
    alpha = np.maximum(alpha, dot)
    rgba = np.zeros(px.shape + (4,), np.float32)
    col, dark = np.array(colour, np.float32) / 255, np.array(outline, np.float32) / 255
    for i in range(3):
        rgba[..., i] = np.where(shade < 0, dark[i], col[i] * (0.75 + 0.25 * np.clip(shade, 0, 1)))
    rgba[..., 3] = alpha
    save(rgba, name)


if __name__ == "__main__":
    disc()
    ring()
    cone()
    arrow_shaft()
    arrow_head()
    crosshair("crosshair_neutral.png", (236, 190, 84), (70, 46, 14))
    crosshair("crosshair_enemy.png", (226, 58, 46), (70, 14, 10), enemy=True)
    crosshair("crosshair_ally.png", (70, 130, 236), (14, 30, 80))
