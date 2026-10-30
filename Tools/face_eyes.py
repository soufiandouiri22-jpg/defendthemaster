#!/usr/bin/env python3
"""Draws a hero's eyes (Config.Heroes[hero].Look.Eyes): his left eye (on the right as seen from the front), and the
right one as its mirror image, on a transparent ground, at four times the size and scaled down so the edges stay smooth. Upload both
through Studio (the Studio MCP's upload_image, from a local http.server on Art/Faces) and put their ids in Config.

    python3 Tools/face_eyes.py Mavorak
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parent.parent
SS = 4
W, H = 256, 160

# Per hero the colours: the iris, its dark pupil, the eye's white and the outline. The shape is the same for every hero:
# a slanted almond with a heavy upper lid, its point at the outer corner.
HEROES = {
    "Mavorak": {
        "iris": (92, 40, 150),
        "pupil": (34, 10, 64),
        "white": (250, 250, 252),
        "line": (14, 10, 16),
    },
}

# The outline of his left eye in fractions of the image, as seen from the front: the inner corner, the upper lid, the
# outer point and the lower lid.
SHAPE = [(0.05, 0.16), (0.70, 0.06), (0.97, 0.56), (0.62, 0.94), (0.10, 0.82)]


def eye(colours: dict) -> Image.Image:
    w, h = W * SS, H * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outer = [(x * w, y * h) for x, y in SHAPE]
    d.polygon(outer, fill=colours["line"] + (255,))
    # The white inside the outline: the same shape, its upper lid thicker than the rest.
    cx, cy = sum(p[0] for p in outer) / 5, sum(p[1] for p in outer) / 5
    inner = []
    for (x, y), (fx, fy) in zip(outer, SHAPE):
        pull = 0.14 if fy < 0.2 else 0.09
        inner.append((x + (cx - x) * pull, y + (cy - y) * pull + (0.05 * h if fy < 0.2 else 0)))
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon(inner, fill=255)
    inside = Image.new("RGBA", (w, h), colours["white"] + (255,))
    di = ImageDraw.Draw(inside)
    # The iris, tall enough to run under both lids, looking straight ahead.
    ix, iy, rx, ry = 0.50 * w, 0.52 * h, 0.25 * w, 0.46 * h
    di.ellipse((ix - rx, iy - ry, ix + rx, iy + ry), fill=colours["iris"] + (255,))
    px, py, pr = ix + 0.01 * w, iy + 0.02 * h, 0.10 * w
    di.ellipse((px - pr, py - pr * 1.2, px + pr, py + pr * 1.2), fill=colours["pupil"] + (255,))
    # The highlight, up and towards the outer corner.
    hx, hy, hr = ix + 0.07 * w, iy - 0.16 * h, 0.05 * w
    di.ellipse((hx - hr, hy - hr, hx + hr, hy + hr), fill=(255, 255, 255, 255))
    img.paste(inside, (0, 0), mask)
    return img.resize((W, H), Image.LANCZOS)


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in HEROES:
        sys.exit(__doc__)
    hero = sys.argv[1]
    out = ROOT / "Art" / "Faces" / hero
    out.mkdir(parents=True, exist_ok=True)
    left = eye(HEROES[hero])
    right = ImageOps.mirror(left)
    left.save(out / "eye_left.png")
    right.save(out / "eye_right.png")
    # As seen from the front: his right eye on the left.
    preview = Image.new("RGBA", (W * 2 + 60, H + 40), (214, 178, 150, 255))
    preview.alpha_composite(right, (20, 20))
    preview.alpha_composite(left, (W + 40, 20))
    preview.save(out / "preview.png")
    print(f"{hero}: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
