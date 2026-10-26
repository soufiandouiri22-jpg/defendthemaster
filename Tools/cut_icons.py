"""Cuts a sheet of ability icons on a white background (Meshy image-to-image, Art/Icons/concepts) into one square PNG
per icon, with the white round it made transparent. Each icon is a cluster of drawing apart from the others; it is cut
at its bounds, centred in a square with a small margin. The icons are named in reading order (row by row, the rows
`rows` bands of the sheet).

    python3 Tools/cut_icons.py <sheet.png> <rows> <out_dir> <name> [<name> ...]
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

SIZE = 256
MARGIN = 0.06


def cut(sheet: Path, rows: int, out: Path, names: list[str]):
    rgb = np.asarray(Image.open(sheet).convert("RGB")).astype(np.float32)
    h, w = rgb.shape[:2]
    lightest = rgb.min(axis=2)
    spread = rgb.max(axis=2) - lightest
    white = (lightest > 228) & (spread < 22)
    # The background is the white that reaches the sheet's edge; white inside a drawing stays.
    labels, _ = ndimage.label(white)
    edge = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    background = np.isin(labels, edge[edge > 0])
    # A soft edge: near the background, the alpha follows how far a pixel is from white.
    near = ndimage.binary_dilation(background, iterations=3) & ~background
    alpha = np.where(background, 0.0, 1.0)
    soft = np.clip((255 - lightest) / 70, 0, 1)
    alpha = np.where(near, np.minimum(alpha, soft), alpha)
    rgba = np.dstack([rgb, alpha * 255]).astype(np.uint8)
    image = Image.fromarray(rgba)

    out.mkdir(parents=True, exist_ok=True)
    drawn = alpha > 0.5
    clusters, count = ndimage.label(ndimage.binary_dilation(drawn, iterations=8))
    boxes = []
    for found in ndimage.find_objects(clusters):
        ys, xs = np.nonzero(drawn[found])
        if len(ys) < 2000:
            continue
        by0, bx0 = found[0].start + ys.min(), found[1].start + xs.min()
        by1, bx1 = found[0].start + ys.max(), found[1].start + xs.max()
        boxes.append((int((by0 + by1) / 2 // (h / rows)), (bx0 + bx1) / 2, bx0, by0, bx1, by1))
    boxes.sort()
    assert len(boxes) == len(names), f"{len(boxes)} icons on the sheet, {len(names)} names"
    for name, (_, _, bx0, by0, bx1, by1) in zip(names, boxes):
        side = max(bx1 - bx0, by1 - by0) * (1 + 2 * MARGIN)
        cx, cy = (bx0 + bx1) / 2, (by0 + by1) / 2
        box = tuple(round(v) for v in (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2))
        icon = image.crop(box).resize((SIZE, SIZE), Image.LANCZOS)
        icon.save(out / f"{name}.png")
        print("wrote", out / f"{name}.png")


if __name__ == "__main__":
    cut(Path(sys.argv[1]), int(sys.argv[2]), Path(sys.argv[3]), sys.argv[4:])
