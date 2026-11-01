"""Draws the four card suits (heart, diamond, club, spade) and a four-pointed star as white PNGs in Art/VFX/cards/,
each a solid shape with a soft glow round it (the suits cut from the owner's sheet in Art/VFX/cards/source), for the sparkles Jestrel's laser beams shed (HeroControls' projectileModel, Config's
Projectile.Cards). White so the game can tint them. Upload them through Studio (the Studio MCP's upload_image, from a
local http.server on Art/VFX/cards) and put their ids in src/shared/Assets.luau.

    python3 Tools/card_textures.py
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Art/VFX/cards"
SIZE = 128
# Drawn this many times larger and scaled down, for smooth edges.
SCALE = 8
# The shape's share of the picture (the rest is room for its glow), and how far the glow reaches.
SHAPE = 0.58
GLOW = 0.07
SUITS = ("heart", "diamond", "club", "spade")
# The owner's sheet of the four suits (2026-11-01); the suits are cut from it rather than drawn while it is there.
SHEET = OUT / "source/playing-cards-symbols.png"


def heart(d: ImageDraw.ImageDraw, c: float, r: float, flip: bool = False):
    """A heart filling the square of half-width r round (c, c); flipped, the top of a spade."""
    lobe = r * 0.52
    top = c - r * 0.42
    sign = -1 if flip else 1
    y_lobes = c + sign * (top - c)
    for x in (c - lobe * 0.95, c + lobe * 0.95):
        d.ellipse((x - lobe, y_lobes - lobe, x + lobe, y_lobes + lobe), fill=255)
    tip = c + sign * r
    d.polygon([(c - r * 0.98, y_lobes + sign * lobe * 0.35), (c + r * 0.98, y_lobes + sign * lobe * 0.35), (c, tip)], fill=255)


def stem(d: ImageDraw.ImageDraw, c: float, r: float, top: float):
    d.polygon([(c - r * 0.08, top), (c + r * 0.08, top), (c + r * 0.36, c + r), (c - r * 0.36, c + r)], fill=255)


def cut(name: str) -> Image.Image:
    """A suit cut from the owner's sheet: heart at the top and diamond at the bottom (red), spade on the left and club
    on the right (black), scaled to the shape's share and centred."""
    sheet = np.asarray(Image.open(SHEET).convert("RGBA"), float)
    h, w = sheet.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w]
    red = sheet[..., 0] > 128
    where = {
        "heart": red & (ys < h / 2),
        "diamond": red & (ys >= h / 2),
        "spade": ~red & (xs < w / 2),
        "club": ~red & (xs >= w / 2),
    }[name]
    # Bounded by its solid pixels only: the soft rims of the red suits read as dark and would stretch a black one's box.
    rows, cols = np.nonzero(where & (sheet[..., 3] > 128))
    top, bottom, left, right = rows.min(), rows.max() + 1, cols.min(), cols.max() + 1
    alpha = np.where(where, sheet[..., 3], 0)
    piece = Image.fromarray(alpha[top:bottom, left:right].astype(np.uint8))
    fit = SIZE * SHAPE / max(piece.size)
    piece = piece.resize((round(piece.width * fit), round(piece.height * fit)), Image.LANCZOS)
    mask = Image.new("L", (SIZE, SIZE), 0)
    mask.paste(piece, ((SIZE - piece.width) // 2, (SIZE - piece.height) // 2))
    return mask


def shape(name: str) -> Image.Image:
    if name in SUITS and SHEET.exists():
        return cut(name)
    big = SIZE * SCALE
    c = big / 2
    r = big * SHAPE / 2
    mask = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(mask)
    if name == "heart":
        heart(d, c, r)
    elif name == "diamond":
        d.polygon([(c, c - r), (c + r * 0.72, c), (c, c + r), (c - r * 0.72, c)], fill=255)
    elif name == "spade":
        heart(d, c - r * 0.12, r * 0.86, flip=True)
        stem(d, c, r, c)
    elif name == "club":
        ball = r * 0.36
        for x, y in ((c, c - r * 0.5), (c - r * 0.5, c + r * 0.08), (c + r * 0.5, c + r * 0.08)):
            d.ellipse((x - ball, y - ball, x + ball, y + ball), fill=255)
        d.ellipse((c - ball * 0.6, c - ball * 0.4, c + ball * 0.6, c + ball * 0.8), fill=255)
        stem(d, c, r, c)
    elif name == "star":
        # A four-pointed sparkle with sharp tips and curved-in sides (an astroid), as twinkles round his portrait's cane.
        points = []
        for i in range(256):
            a = i / 256 * 2 * np.pi
            x, y = np.cos(a), np.sin(a)
            points.append((c + r * np.sign(x) * abs(x) ** 4.5, c + r * np.sign(y) * abs(y) ** 4.5))
        d.polygon(points, fill=255)
    return mask.resize((SIZE, SIZE), Image.LANCZOS)


def save(name: str):
    solid = shape(name)
    glow = solid.filter(ImageFilter.GaussianBlur(SIZE * GLOW))
    alpha = np.maximum(np.asarray(solid, float), np.asarray(glow, float) * 0.85)
    rgba = np.zeros((SIZE, SIZE, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = alpha.clip(0, 255).astype(np.uint8)
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba).save(OUT / f"{name}.png")
    print(OUT / f"{name}.png")


def main():
    for name in (*SUITS, "star"):
        save(name)


if __name__ == "__main__":
    main()
