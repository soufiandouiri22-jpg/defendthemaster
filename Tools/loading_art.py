"""The loading screen's three pictures: the colosseum (Art/UI/loading_plate.png), the logo on its own
(Art/UI/loading_mark.png) so it is drawn from a texture of its own at full sharpness, and the logo's warm glow and
shadow (Art/UI/loading_glow.png), which the game lays under the logo wherever the logo stands.

    python3 Tools/loading_art.py <colosseum plate image>

Roblox keeps at most 1024 pixels a side, so the plate and the logo are saved at that size and nothing is scaled down
again on upload. The glow is drawn round the logo at LOGO_WIDTH (its width on the 1280-wide picture) times GLOW_SCALE,
with GLOW_PAD of that around it on every side; src/first/Loading.luau sizes it by the printed shares of the logo."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).parent))
from key_icons import bleed  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "Docs/Designs/Logo/dtm_logo_main.png"
W, H = 1280, 720
LOGO_WIDTH = 440
OUT_W, OUT_H = 1024, 576
MARK = 1024
GLOW_SCALE = 1.5
GLOW_PAD = 0.2


def plate(source: Path) -> Image.Image:
    return Image.open(source).convert("RGB").resize((OUT_W, OUT_H), Image.LANCZOS)


def glow(logo: Image.Image) -> Image.Image:
    lw = round(LOGO_WIDTH * GLOW_SCALE)
    small = logo.resize((lw, round(logo.height * lw / logo.width)), Image.LANCZOS)
    pad = round(lw * GLOW_PAD)
    size = (small.width + 2 * pad, small.height + 2 * pad)
    a = Image.new("L", size, 0)
    a.paste(small.getchannel("A"), (pad, pad))

    def layer(color, alpha, blur, dy):
        m = a.point(lambda v: v * alpha).filter(ImageFilter.GaussianBlur(blur * GLOW_SCALE))
        m = m.transform(size, Image.AFFINE, (1, 0, 0, 0, 1, -dy * GLOW_SCALE))
        out = Image.new("RGBA", size, color)
        out.putalpha(m)
        return out

    out = Image.alpha_composite(layer((255, 190, 90, 255), 0.45, 18, 0), layer((25, 10, 5, 255), 0.6, 8, 8))
    rgba = np.asarray(out).copy()
    seen = rgba[..., 3] > 0
    if seen.any():
        _, (iy, ix) = ndimage.distance_transform_edt(~seen, return_indices=True)
        rgba[..., :3][~seen] = rgba[..., :3][iy[~seen], ix[~seen]]
    return Image.fromarray(rgba)


def mark(logo: Image.Image) -> Image.Image:
    scale = min(1.0, MARK / max(logo.size))
    size = (round(logo.width * scale), round(logo.height * scale))
    rgba = np.asarray(logo, dtype=np.float32)
    a = rgba[..., 3:4] / 255.0
    pre = np.dstack([rgba[..., :3] * a, rgba[..., 3:4]])
    channels = [np.asarray(Image.fromarray(pre[..., i]).resize(size, Image.LANCZOS), dtype=np.float32) for i in range(4)]
    out = np.dstack(channels)
    alpha = np.clip(out[..., 3], 0, 255)
    colour = out[..., :3] / np.maximum(alpha[..., None] / 255.0, 1e-3)
    rgba = np.dstack([np.clip(colour, 0, 255), alpha]).round().astype(np.uint8)
    return Image.fromarray(bleed(rgba))


def main():
    logo = Image.open(LOGO).convert("RGBA")
    logo = logo.crop(logo.getchannel("A").getbbox())
    plate(Path(sys.argv[1])).save(ROOT / "Art/UI/loading_plate.png")
    m = mark(logo)
    m.save(ROOT / "Art/UI/loading_mark.png")
    g = glow(logo)
    g.save(ROOT / "Art/UI/loading_glow.png")
    lw = round(LOGO_WIDTH * GLOW_SCALE)
    lh = round(logo.height * lw / logo.width)
    print("mark", m.size, "logo height share", round(logo.height * LOGO_WIDTH / logo.width) / H)
    print("glow", g.size, "glow size in logos", g.width / lw, g.height / lh)


if __name__ == "__main__":
    main()
