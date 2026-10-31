"""The loading screen's blade (Art/UI/loading_blade.png): the Master's greatsword
(Art/Concepts/Greatsword/master_greatsword_A.png) as a clean white emblem lying flat with its tip to the right, drawn
here from his sword's shapes (round pommel, grip, the guard's two scrolls curling towards the blade, the gem, the
blade with its fuller and point) with the gem and fuller cut in as dark lines, and a black rim round it so that where
two blades cross the one on top stands clear of the other; and the soft white light they cross in
(Art/UI/loading_light.png).

    python3 Tools/loading_blades.py         # the blade with its sharp corners
    python3 Tools/loading_blades.py soft    # a softer, rounder one (Art/UI/loading_blade_soft.png)

Drawn SUPER times larger and scaled down for smooth edges; both pictures stay within Roblox's 1024 pixels a side."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
BLADE = ROOT / "Art/UI/loading_blade.png"
BLADE_SOFT = ROOT / "Art/UI/loading_blade_soft.png"
LIGHT = ROOT / "Art/UI/loading_light.png"
# The sword in the concept's pixels (1024 wide), its length along y = MID.
W, H, MID = 1024, 310, 155
SUPER = 4
# The black rim round it and the darkness of the cut-in lines (0 black, 1 white).
RIM, LINE = 7, 0.12
# How round the soft blade's corners are (the blur that rounds them, in the concept's pixels).
SOFT = 6
LIGHT_SIZE = 512


def blade(soft: bool = False) -> Image.Image:
    s = SUPER
    white = Image.new("L", (W * s, H * s), 0)
    lines = Image.new("L", (W * s, H * s), 0)
    d = ImageDraw.Draw(white)
    k = ImageDraw.Draw(lines)

    def p(x: float, y: float) -> tuple[float, float]:
        return (x * s, (MID + y) * s)

    def circle(draw: ImageDraw.ImageDraw, x: float, y: float, r: float, **kw):
        draw.ellipse([*p(x - r, y - r), *p(x + r, y + r)], **kw)

    if soft:
        return finish_soft(white, lines, d, k, p, circle)

    # The pommel and the grip.
    circle(d, 46, 0, 31, fill=255)
    d.rounded_rectangle([*p(60, -19), *p(318, 19)], radius=10 * s, fill=255)
    # The blade: straight edges to the shoulders of the point.
    d.polygon([p(330, -52), p(912, -52), p(1004, 0), p(912, 52), p(330, 52)], fill=255)
    # The guard: a bar across the grip, thickest at the blade, whose two ends sweep towards the blade into round knobs.
    d.polygon([p(304, -78), p(344, -86), p(344, 86), p(304, 78)], fill=255)
    for side in (-1, 1):
        d.line([p(324, side * 70), p(334, side * 98), p(356, side * 114)], fill=255, width=40 * s, joint="curve")
        circle(d, 324, side * 70, 20, fill=255)
        circle(d, 360, side * 114, 24, fill=255)
    # The gem on the guard, an outlined hexagon, and the fuller down the blade.
    hexagon = [p(326 + 17 * math.cos(math.radians(a)), 17 * math.sin(math.radians(a))) for a in range(0, 360, 60)]
    k.polygon(hexagon, outline=255, width=5 * s)
    k.rounded_rectangle([*p(400, -4), *p(860, 4)], radius=4 * s, fill=255)

    shape = np.asarray(white, np.float32) / 255
    cut = np.asarray(lines, np.float32) / 255 * (shape > 0.5)
    rim = ndimage.binary_dilation(shape > 0.5, iterations=RIM * s).astype(np.float32)
    return emblem(shape, cut, rim)


def finish_soft(white, lines, d, k, p, circle) -> Image.Image:
    """The softer blade: the same sword, chunkier, like a toy sword: a big round pommel, a thick grip, the guard one
    round-ended bar, every corner rounded (the point too), the gem a round and the fuller a thick rounded groove."""
    s = SUPER
    circle(d, 56, 0, 42, fill=255)
    d.rounded_rectangle([*p(70, -27), *p(320, 27)], radius=27 * s, fill=255)
    d.polygon([p(336, -66), p(850, -66), p(952, -18), p(952, 18), p(850, 66), p(336, 66)], fill=255)
    circle(d, 952, 0, 18, fill=255)
    d.rounded_rectangle([*p(288, -122), *p(358, 122)], radius=35 * s, fill=255)
    shape = np.asarray(white, np.float32) / 255
    # Every corner rounded: blurred and cut at half, which rounds the outer corners and fills the inner ones.
    shape = (ndimage.gaussian_filter(shape, SOFT * s) > 0.5).astype(np.float32)
    circle(k, 323, 0, 16, outline=255, width=7 * s)
    k.rounded_rectangle([*p(410, -9), *p(820, 9)], radius=9 * s, fill=255)
    cut = np.asarray(lines, np.float32) / 255 * (shape > 0.5)
    rim = (ndimage.distance_transform_edt(shape < 0.5) <= RIM * s).astype(np.float32)
    return emblem(shape, cut, rim)


def emblem(shape: np.ndarray, cut: np.ndarray, rim: np.ndarray) -> Image.Image:
    colour = 1 - (1 - LINE) * cut
    lit = shape * colour
    alpha = np.maximum(shape, rim)
    rgb = np.where(alpha > 0, lit / np.maximum(alpha, 1e-3), 0)
    big = np.zeros(shape.shape + (4,), np.float32)
    big[..., 0] = big[..., 1] = big[..., 2] = rgb * alpha
    big[..., 3] = alpha
    small = [np.asarray(Image.fromarray(big[..., i] * 255).resize((W, H), Image.LANCZOS), np.float32) for i in range(4)]
    a = np.clip(small[3], 0, 255)
    c = np.clip(small[0] / np.maximum(a / 255, 1e-3), 0, 255)
    out = np.zeros((H, W, 4), np.uint8)
    out[..., 0] = out[..., 1] = out[..., 2] = c.round().astype(np.uint8)
    out[..., 3] = a.round().astype(np.uint8)
    return Image.fromarray(out)


def light() -> Image.Image:
    r = np.linspace(-1, 1, LIGHT_SIZE)
    d = np.hypot(*np.meshgrid(r, r))
    a = np.clip(1 - d, 0, 1) ** 2.2
    out = np.zeros((LIGHT_SIZE, LIGHT_SIZE, 4), np.uint8)
    out[..., :3] = 255
    out[..., 3] = (a * 255).round().astype(np.uint8)
    return Image.fromarray(out)


def main():
    soft = "soft" in sys.argv[1:]
    b = blade(soft)
    b.save(BLADE_SOFT if soft else BLADE)
    light().save(LIGHT)
    print("blade", b.size, "aspect", round(b.width / b.height, 4))


if __name__ == "__main__":
    main()
