#!/usr/bin/env python3
"""Turns a drawing of light on black (a GenerateImage bolt or glow) into a texture for Beams and particles: white, with
the drawing's brightness as its alpha, so the effect tints it any colour (LightningEffects). Crops to the rows where the
light is, with a little margin, so a Beam's width is spent on it.

    python3 Tools/light_texture.py <drawing> <out.png> [--width 1024]
"""

import sys

from PIL import Image


def main() -> int:
    args = sys.argv[1:]
    width = 1024
    if "--width" in args:
        i = args.index("--width")
        width = int(args[i + 1])
        del args[i : i + 2]
    if len(args) != 2:
        sys.exit(__doc__)
    image = Image.open(args[0]).convert("L")
    # Darker than this is the background (a JPEG's noise in the black).
    alpha = image.point(lambda v: 0 if v < 12 else min(255, int((v - 12) * 255 / 243)))
    box = alpha.point(lambda v: 255 if v > 24 else 0).getbbox()
    if not box:
        sys.exit("no light in the drawing")
    margin = max(8, (box[3] - box[1]) // 8)
    top, bottom = max(0, box[1] - margin), min(alpha.height, box[3] + margin)
    alpha = alpha.crop((0, top, alpha.width, bottom))
    height = max(16, round(alpha.height * width / alpha.width))
    alpha = alpha.resize((width, height), Image.LANCZOS)
    out = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    out.save(args[1])
    print(f"{args[1]}: {out.width} x {out.height}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
