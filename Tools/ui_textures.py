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


def smin(a, b, k):
    """A union of two distance fields with a rounded fillet of about k where they meet."""
    h = np.clip(k - np.abs(a - b), 0, None) / k
    return np.minimum(a, b) - h * h * k / 4


def rounded_box(x, y, cx, cy, hx, hy, r):
    qx, qy = np.abs(x - cx) - (hx - r), np.abs(y - cy) - (hy - r)
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r


def paint(rgba, mask, colour):
    """Lays `colour` (one colour, or one per pixel) over rgba where mask is 1."""
    for i in range(3):
        c = colour[..., i] if np.ndim(colour) > 1 else colour[i]
        rgba[..., i] = rgba[..., i] * (1 - mask) + c * mask


def rgb(*c):
    return np.array(c, np.float32) / 255


def polygon_sdf(x, y, points):
    """Distance to a closed polygon (negative inside)."""
    d = np.full(x.shape, np.inf, np.float32)
    inside = np.zeros(x.shape, bool)
    n = len(points)
    for i in range(n):
        (ax, ay), (bx, by) = points[i], points[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        px, py = x - ax, y - ay
        t = np.clip((px * ex + py * ey) / (ex * ex + ey * ey), 0, 1)
        d = np.minimum(d, np.hypot(px - ex * t, py - ey * t))
        crosses = (ay > y) != (by > y)
        inside ^= crosses & (x < ax + (y - ay) * ex / np.where(by == ay, 1, by - ay))
    return np.where(inside, -d, d)


def team_crown(name, body, deep, light, line):
    """The top bar's crown (design 05) in its team's colours: one flat body with a zigzag top of three points, balls
    on their tips, a band under it behind a dark line, a dark outline, and light catching the upper left edges."""
    w, h = 160, 150
    x, y = grid(w, h)
    side_tip, mid_tip, valley, split, foot = 38, 22, 66, 104, 138
    left, right = 22, w - 22
    top = [(left, split), (left, side_tip), (w * 0.35, valley), (w / 2, mid_tip), (w * 0.65, valley), (right, side_tip),
           (right, split)]

    def shape(dx, dy):
        upper = polygon_sdf(x - dx, y - dy, top)
        lower = rounded_box(x - dx, y - dy, w / 2, (split + foot) / 2, (right - left) / 2 + 3, (foot - split) / 2, 5)
        balls = [np.hypot(x - dx - tx, y - dy - ty) - 11 for tx, ty in ((left, side_tip), (w / 2, mid_tip),
                                                                         (right, side_tip))]
        return np.minimum.reduce([upper - 2, lower] + balls)

    d = shape(0, 0)
    outline = 6
    rgba = np.zeros(x.shape + (4,), np.float32)
    t = np.clip((y - mid_tip) / (foot - mid_tip), 0, 1)[..., None]
    paint(rgba, np.ones_like(x), body * (1 - t) + deep * t)
    paint(rgba, coverage(d) * coverage(-shape(6, 6)), light)
    paint(rgba, band(y - split, 5) * coverage(d), line)
    for tx, ty in ((left, side_tip), (w / 2, mid_tip), (right, side_tip)):
        ball = np.hypot(x - tx, y - ty) - 11
        paint(rgba, coverage(ball), light)
        paint(rgba, band(ball, 3.5) * (y > ty + 2), line)
        paint(rgba, coverage(np.hypot(x - tx + 3.5, y - ty + 3.5) - 3.5), rgb(255, 255, 255))
    paint(rgba, coverage(-d) * coverage(d - outline), line)
    rgba[..., 3] = coverage(d - outline)
    save(rgba, name)


# The score board of design 05, in the HUD's 1080-line units: a cream board with a dark tab hanging under its middle
# for the clock. Drawn at 1.5 times its size on screen.
BOARD_W, BOARD_H, TAB_H = 672, 88, 48
BOARD_K = 1.5


def scoreboard():
    pad = 4
    w, h = round((BOARD_W + 2 * pad) * BOARD_K), round((BOARD_H + TAB_H + 2 * pad) * BOARD_K)
    x, y = grid(w, h)
    x, y = x / BOARD_K - pad, y / BOARD_K - pad
    cx = BOARD_W / 2
    board = rounded_box(x, y, cx, BOARD_H / 2, BOARD_W / 2, BOARD_H / 2, 18)
    bottom = BOARD_H + TAB_H
    slant = np.clip(y - BOARD_H, 0, None) * 0.3
    tab = rounded_box(x + np.sign(x - cx) * slant, y, cx, (BOARD_H - 20 + bottom) / 2, 100, (bottom - BOARD_H + 20) / 2, 16)
    d = smin(board, tab, 16)
    outline = 3.5
    rgba = np.zeros(x.shape + (4,), np.float32)
    t = np.clip(y / BOARD_H, 0, 1)[..., None]
    paint(rgba, np.ones_like(x), rgb(255, 238, 196) * (1 - t) + rgb(246, 206, 148) * t)
    paint(rgba, band(y - 7, 2.5) * coverage(board + 6), rgb(255, 250, 232))
    paint(rgba, coverage(board + outline) * np.clip((y - (BOARD_H - 12)) / 2, 0, 1), rgb(226, 182, 122))
    split = BOARD_H - 3
    below = np.clip((y - split) * 2, 0, 1)
    tt = np.clip((y - split) / TAB_H, 0, 1)[..., None]
    paint(rgba, below, rgb(82, 52, 26) * (1 - tt) + rgb(52, 30, 12) * tt)
    paint(rgba, band(y - (split + 3), 2) * coverage(tab + 7), rgb(126, 86, 46))
    paint(rgba, coverage(-d) * coverage(d - outline), rgb(58, 30, 8))
    rgba[..., 3] = coverage(d - outline)
    save(rgba, "hud_scoreboard.png")


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


def edge_arrow():
    """The tips' arrow pointing at a goal (Tips.Path): a bold gold arrowhead pointing up
    with a dark outline, a lighter top half and a white gleam, as the HUD's gold."""
    n = 160
    x, y = grid(n, n)
    points = [(n / 2, 10), (n - 14, n - 30), (n / 2, n - 58), (14, n - 30)]
    d = polygon_sdf(x, y, points)
    outline = 7
    rgba = np.zeros(x.shape + (4,), np.float32)
    light = np.clip(1.15 - y / n * 0.55, 0, 1.2)
    paint(rgba, coverage(d), np.stack([255 / 255 * light, 206 / 255 * light, 74 / 255 * light], -1))
    gleam = coverage(polygon_sdf(x, y, [(n / 2, 24), (n / 2 + 16, 52), (n / 2, 46)]) + 1)
    paint(rgba, gleam * 0.8, rgb(255, 250, 220))
    paint(rgba, coverage(-d) * coverage(d - outline), rgb(58, 30, 8))
    rgba[..., 3] = coverage(d - outline)
    save(rgba, "tutorial_edge_arrow.png")


if __name__ == "__main__":
    import sys

    if sys.argv[1:] == ["tutorial"]:
        edge_arrow()
        sys.exit()
    crown()
    team_crown("hud_crown_blue.png", rgb(30, 146, 246), rgb(12, 108, 214), rgb(140, 206, 255), rgb(10, 22, 44))
    team_crown("hud_crown_red.png", rgb(236, 52, 44), rgb(186, 26, 22), rgb(255, 150, 136), rgb(44, 10, 8))
    scoreboard()
    coin()
    disc()
    ring()
    cone()
    arrow_shaft()
    arrow_head()
    crosshair("crosshair_neutral.png", (236, 190, 84), (70, 46, 14))
    crosshair("crosshair_enemy.png", (226, 58, 46), (70, 14, 10), enemy=True)
    crosshair("crosshair_ally.png", (70, 130, 236), (14, 30, 80))
