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


def crown_sdf(x, y, w, h):
    """A crown filling a w x h box: a band with three points, each tipped with a ball (distance, negative inside)."""
    band_top, band_bottom = h * 0.62, h * 0.9
    left, right = w * 0.12, w * 0.88
    d_band = np.maximum(np.maximum(left - x, x - right), np.maximum(band_top - y, y - band_bottom))
    d = d_band
    tips = [(w * 0.18, h * 0.24), (w * 0.5, h * 0.1), (w * 0.82, h * 0.24)]
    for tx, ty in tips:
        # A point from the band up to its tip, as wide at the band as a third of it.
        half = w * 0.19
        base_y = band_top + 2
        k = half / (base_y - ty)
        d_side = (np.abs(x - tx) - k * (y - ty)) / np.sqrt(1 + k * k)
        d_point = np.maximum(np.maximum(d_side, np.maximum(ty - y, y - base_y)), np.maximum(left - x, x - right))
        d = np.minimum(d, d_point)
        d = np.minimum(d, np.hypot(x - tx, y - ty) - w * 0.075)
    return d, band_top, band_bottom


def crown():
    """The Master's crown over his team's health bar (design 05): white and grey shading under a dark outline, so the
    game tints it in the team's colour; a lighter band with three jewels."""
    w, h = 160, 136
    x, y = grid(w, h)
    d, band_top, band_bottom = crown_sdf(x, y, w, h)
    outline = 7
    inside = coverage(d)
    alpha = coverage(d - outline)
    light = np.clip(1.0 - 0.45 * (y / h), 0, 1)
    shade = np.where(inside > 0, light, 0.18)
    band = (y > band_top + 4) & (y < band_bottom - 4) & (inside > 0.5)
    shade = np.where(band, np.clip(light + 0.12, 0, 1), shade)
    for jx in (0.3, 0.5, 0.7):
        jewel = coverage(np.hypot(x - w * jx, y - (band_top + band_bottom) / 2) - h * 0.06)
        shade = np.where(jewel > 0.5, 0.55, shade)
    rgba = np.zeros(x.shape + (4,), np.float32)
    for i in range(3):
        rgba[..., i] = shade
    rgba[..., 3] = alpha
    save(rgba, "hud_crown.png")


def coin():
    """The coin of the coin counter (design 05): gold with a darker rim, an inner ring and a raised crown."""
    n = 128
    x, y = grid(n, n)
    r = np.hypot(x - n / 2, y - n / 2)
    edge = n / 2 - 4
    alpha = coverage(r - edge)
    gold = np.array((246, 196, 64), np.float32) / 255
    deep = np.array((176, 116, 24), np.float32) / 255
    dark = np.array((94, 56, 12), np.float32) / 255
    light = np.clip(1.15 - 0.5 * ((x + y) / (2 * n)), 0, 1.2)
    rgba = np.zeros(x.shape + (4,), np.float32)
    for i in range(3):
        rgba[..., i] = gold[i] * light
    rim = coverage(-(r - (edge - 9)))
    inner = band(r - (edge - 18), 3)
    cw, ch = n * 0.5, n * 0.42
    cd, _, _ = crown_sdf(x - (n - cw) / 2, y - (n - ch) / 2 - 2, cw, ch)
    raised = coverage(cd)
    raised_edge = band(cd, 3)
    for i in range(3):
        c = rgba[..., i]
        c = np.where(rim > 0.5, deep[i] * light, c)
        c = c * (1 - inner) + dark[i] * inner
        c = c * (1 - raised) + (gold[i] * 1.12) * raised
        c = c * (1 - raised_edge) + deep[i] * raised_edge
        rgba[..., i] = c
    outline = band(r - edge, 3)
    for i in range(3):
        rgba[..., i] = rgba[..., i] * (1 - outline) + dark[i] * outline
    rgba[..., 3] = alpha
    save(rgba, "hud_coin.png")


if __name__ == "__main__":
    crown()
    coin()
    disc()
    ring()
    cone()
    arrow_shaft()
    arrow_head()
    crosshair("crosshair_neutral.png", (236, 190, 84), (70, 46, 14))
    crosshair("crosshair_enemy.png", (226, 58, 46), (70, 14, 10), enemy=True)
    crosshair("crosshair_ally.png", (70, 130, 236), (14, 30, 80))
