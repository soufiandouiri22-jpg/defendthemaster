"""Draws the sniper's scope (Corvin's R, src/client/Scope.luau) as two PNGs in Art/UI/:

- scope_housing.png: the eyepiece seen from behind, the lens's edge at LENS of the image's radius: the glass (dark
  towards its edge, a faint colour fringe, a crescent of light on its upper left), the inner lip, the gunmetal tube
  with its grip ribs and engraved marks, an orange zero mark at the top, the outer bevel, and a soft shadow round it.
- scope_reticle.png: the crosshair, as wide as the lens: tapered posts from the rim, fine hairs with a gap round the
  middle, tick marks along the level hair, bullet-drop bars under the middle, four arcs round it; every line has a thin
  light edge so it reads on dark ground as well.
Drawn at twice the size and scaled down, as Tools/ui_textures.py does. Upload them through Studio (the Studio MCP's
upload_image, from a local http.server on Art/UI) and put their ids in src/shared/Assets.luau.

    python3 Tools/scope_textures.py
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "Art" / "UI"
SS = 2
N = 1024
# The lens's edge as a share of the housing image's radius; Scope.luau sizes the image by it.
LENS = 0.74


def grid(n):
    ys, xs = np.mgrid[0 : n * SS, 0 : n * SS].astype(np.float32)
    return (xs + 0.5) / SS - n / 2, (ys + 0.5) / SS - n / 2


def coverage(d, soft=0.8):
    return np.clip(0.5 - d / soft, 0, 1)


def band(d, width):
    return coverage(np.abs(d) - width / 2)


def smooth(a, b, t):
    t = np.clip((t - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def rgb(*c):
    return np.array(c, np.float32) / 255


def over(rgba, colour, alpha):
    """Lays `colour` (one colour or one per pixel) with `alpha` over rgba (straight alpha)."""
    a0 = rgba[..., 3]
    a = alpha + a0 * (1 - alpha)
    safe = np.where(a > 0, a, 1)
    for i in range(3):
        c = colour[..., i] if np.ndim(colour) > 1 else colour[i]
        rgba[..., i] = (c * alpha + rgba[..., i] * a0 * (1 - alpha)) / safe
    rgba[..., 3] = a


def save(rgba, name):
    n = rgba.shape[0] // SS
    img = Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8))
    img = img.resize((n, n), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / name)
    print("wrote", OUT / name, img.size)


def housing():
    x, y = grid(N)
    r = np.hypot(x, y)
    angle = np.arctan2(y, x)
    # Light from the upper left: 1 facing it, 0 facing away.
    lit = 0.5 + 0.5 * np.cos(angle - np.radians(-135))
    half = N / 2
    lens = LENS * half
    lip, body, groove, bevel = lens + 9, lens + 58, lens + 34, lens + 65
    rgba = np.zeros(x.shape + (4,), np.float32)

    # The glass: darker towards the edge, a cool fringe and a warm one just inside it, a crescent of light.
    inside = coverage(r - lens)
    over(rgba, rgb(4, 6, 8), 0.62 * smooth(0.62 * lens, lens, r) ** 1.6 * inside)
    over(rgba, rgb(90, 200, 255), 0.22 * band(r - (lens - 5), 4) * inside)
    over(rgba, rgb(255, 120, 200), 0.12 * band(r - (lens - 10), 4) * inside)
    outer = np.hypot(x + 0.16 * lens, y + 0.2 * lens) - 0.86 * lens
    inner = np.hypot(x + 0.06 * lens, y + 0.07 * lens) - 0.86 * lens
    crescent = coverage(outer, 6) * (1 - coverage(inner, 18))
    over(rgba, rgb(255, 255, 255), 0.13 * crescent * inside)

    # The inner lip: near black, with a fine line of light where it meets the glass.
    ring_lip = coverage(r - lip) * (1 - coverage(r - lens))
    over(rgba, rgb(10, 11, 13), ring_lip)
    over(rgba, rgb(200, 210, 225), band(r - (lens + 2), 1.6) * (0.25 + 0.6 * lit))

    # The tube: gunmetal, rounded across its width, lit from the upper left.
    tube = coverage(r - body) * (1 - coverage(r - lip))
    across = np.clip((r - lip) / (body - lip), 0, 1)
    profile = np.clip(np.sin(np.pi * across), 0, 1) ** 0.7
    shade = 0.45 + 0.4 * profile + 0.45 * (lit - 0.5)
    metal = rgb(52, 56, 63)[None, None, :] * shade[..., None]
    # Grip ribs on its outer part, beyond the groove.
    ribs = np.cos(angle * 150) * (r > groove)
    metal = metal * (1 + 0.16 * ribs[..., None])
    over(rgba, np.clip(metal, 0, 1), tube)
    over(rgba, rgb(8, 9, 11), band(r - groove, 2.4) * tube)
    over(rgba, rgb(150, 160, 175), band(r - (groove + 2.2), 1) * (0.15 + 0.35 * lit) * tube)

    # Engraved marks every 30 degrees on the inner part, and the orange zero mark at the top.
    for k in range(12):
        a = np.radians(k * 30 - 90)
        u = x * np.cos(a) + y * np.sin(a)
        v = -x * np.sin(a) + y * np.cos(a)
        long = 14 if k % 3 == 0 else 8
        mark = coverage(np.abs(v) - 1.2) * coverage(np.abs(u - (lip + 4 + long / 2)) - long / 2)
        if k != 0:
            over(rgba, rgb(210, 216, 226), 0.55 * mark)
    tip, base, wide = lip + 3, lip + 22, 9
    k = wide / (base - tip)
    d_side = (np.abs(x) - k * (-y - tip)) / np.sqrt(1 + k * k)
    zero = np.maximum(d_side, np.maximum(tip + y, -y - base))
    over(rgba, rgb(30, 14, 4), coverage(zero - 1.6))
    over(rgba, rgb(255, 150, 40), coverage(zero))
    over(rgba, rgb(255, 220, 150), coverage(zero + 2.2) * np.clip(1 - (-y - tip) / (base - tip), 0, 1) * 0.6)

    # The outer bevel: bright where the light falls, dark where it does not.
    rim = coverage(r - bevel) * (1 - coverage(r - body))
    over(rgba, np.clip(rgb(150, 158, 170)[None, None, :] * (0.25 + 0.9 * lit[..., None]), 0, 1), rim)
    over(rgba, rgb(6, 7, 8), band(r - bevel, 1.6))

    # The shadow round it.
    out = 1 - coverage(r - bevel)
    fade = 1 - smooth(bevel, half - 2, r)
    over(rgba, rgb(0, 0, 0), 0.7 * np.exp(-np.maximum(r - bevel, 0) / 30) * fade * out)
    save(rgba, "scope_housing.png")


def reticle():
    x, y = grid(N)
    r = np.hypot(x, y)
    edge = N / 2
    lens = coverage(r - (edge - 2))
    ink = np.zeros_like(x)

    def add(d):
        nonlocal ink
        ink = np.maximum(ink, coverage(d))

    gap = 13
    hair = 1.6
    line = 1.5
    # The fine hairs, with a gap round the middle.
    add(np.maximum(np.abs(y) - hair, gap - np.abs(x)))
    add(np.maximum(np.abs(x) - hair, gap - np.abs(y)))
    # Tapered posts from the rim: 18 wide, coming to a point at 0.56 of the radius.
    start, full = 0.56 * edge, 0.7 * edge
    for u, v in ((x, y), (-x, y), (y, x), (-y, x)):
        width = 9 * np.clip((u - start) / (full - start), 0, 1)
        add(np.maximum(np.abs(v) - np.maximum(width, hair), start - u))
    # Ticks along the level hair, longer every second one, and three above the middle.
    step = 0.075 * edge
    for i in range(1, 7):
        long = 14 if i % 2 == 0 else 8
        for side in (-1, 1):
            add(np.maximum(np.abs(x - side * i * step) - line, np.abs(y) - long))
        if i <= 3:
            add(np.maximum(np.abs(y + i * step) - line, np.abs(x) - long))
    # Bullet-drop bars under the middle, narrowing with the distance, their ends bent down.
    for i, w in enumerate((0.13, 0.1, 0.078, 0.06)):
        at = (0.11 + i * 0.1) * edge
        add(np.maximum(np.abs(y - at) - line, np.abs(x) - w * edge))
        for side in (-1, 1):
            add(np.maximum(np.abs(x - side * w * edge) - line, np.abs(y - at - 5) - 5))
    # Four arcs round the middle, open where the hairs cross.
    a = np.abs(np.degrees(np.arctan2(y, x))) % 90
    add(np.maximum(np.abs(r - 34) - 1.3, 20 - np.minimum(a, 90 - a)))

    ink *= lens
    # A light edge round every line: the ink grown by a little more than a pixel, behind it.
    img = Image.fromarray((ink * 255).astype(np.uint8))
    grown = np.asarray(img.filter(ImageFilter.MaxFilter(5)), np.float32) / 255
    halo = np.clip(grown - ink, 0, 1) * lens
    rgba = np.zeros(x.shape + (4,), np.float32)
    over(rgba, rgb(235, 240, 235), 0.28 * halo)
    over(rgba, rgb(8, 9, 10), 0.95 * ink)
    save(rgba, "scope_reticle.png")


if __name__ == "__main__":
    housing()
    reticle()
