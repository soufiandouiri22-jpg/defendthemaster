"""Cuts a sheet of icons on a light background (Meshy or GenerateImage, Art/Icons/concepts) into one square PNG per
icon with a clean transparent edge.

    python3 Tools/cut_icons.py <sheet> <out_dir> [--bottom] <name> [<name> ...]

The icons are found on the sheet and named in reading order (row by row, left to right); a name "-" skips one. Each is
cut at the bounds of its drawing into a square with a small margin, centred, or with --bottom standing on the
square's foot (crests with a plate under them).

The edge is what used to go wrong, so it is done in three steps:
- the mask comes from BiRefNet (rembg's birefnet-general, run on the Mac), first over the whole sheet to find the
  icons and then once more on each icon alone for a finer edge, instead of a threshold on "near white", which took
  light parts of a drawing for background and left the background's glow on it;
- the background's colour is taken out of every half-transparent edge pixel (colour = (pixel - (1 - a) * background)
  / a), so no light rim is left round the icon on a dark interface;
- the icon is scaled down premultiplied, so the colour of the transparent pixels around it cannot bleed into its edge.

White background walled in by the drawing (a trophy's handles) is opened and a light rim left round the outline is
taken off as the last step; for icons already cut:

    python3 Tools/cut_icons.py --holes <icon.png> [<icon.png> ...]

Check the result on a dark and on a light ground side by side:

    python3 Tools/cut_icons.py --check <out.png> <icon.png> [<icon.png> ...]
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from rembg import new_session, remove
from scipy import ndimage

SIZE = 256
MARGIN = 0.06
# Alpha below this is dropped and the rest stretched over the full range, which takes off a faint halo.
CHOKE = 0.06
# Parts of one icon closer than this (in sheet pixels) belong together (a crown's points, a ribbon's ends).
JOIN = 14
# Pieces smaller than this share of the largest icon are specks, not icons.
SPECK = 0.04
# A hole (open_holes, on the 256-pixel icon): at least this many pixels of at least this white, walled in by an
# outline at most this light. The white cores of slashes and the shine on metal are smaller or lie in lighter colours.
HOLE_AREA = 300
HOLE_WHITE = 240
HOLE_WALL = 30
# An edge this much lighter than the outline inside it is a rim of the background (fringe); defringe drops its alpha
# below DEFRINGE_CHOKE. A glow (Shadowren's icons) has no dark outline, so it is never this much lighter.
FRINGE = 40
DEFRINGE_CHOKE = 60

session = None


def mask(image: Image.Image) -> np.ndarray:
    """BiRefNet's alpha for `image`, 0 to 1."""
    global session
    if session is None:
        session = new_session("birefnet-general")
    out = remove(image, session=session, only_mask=True, post_process_mask=False)
    return np.asarray(out, dtype=np.float32) / 255.0


def background_colour(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    clear = alpha < 0.02
    return np.median(rgb[clear], axis=0) if clear.any() else np.array([255.0, 255.0, 255.0])


def decontaminate(rgb: np.ndarray, alpha: np.ndarray, back: np.ndarray) -> np.ndarray:
    a = alpha[..., None]
    pure = (rgb - (1 - a) * back) / np.maximum(a, 1e-3)
    return np.where(a > 0.02, np.clip(pure, 0, 255), rgb)


def premultiplied_resize(rgba: np.ndarray, size: int) -> np.ndarray:
    a = rgba[..., 3:4] / 255.0
    pre = np.dstack([rgba[..., :3] * a, rgba[..., 3:4]]).astype(np.float32)
    channels = [
        np.asarray(Image.fromarray(pre[..., i]).resize((size, size), Image.LANCZOS), dtype=np.float32) for i in range(4)
    ]
    out = np.dstack(channels)
    alpha = np.clip(out[..., 3], 0, 255)
    colour = out[..., :3] / np.maximum(alpha[..., None] / 255.0, 1e-3)
    return np.dstack([np.clip(colour, 0, 255), alpha]).round().astype(np.uint8)


def open_holes(rgba: np.ndarray) -> tuple[np.ndarray, int]:
    """Clears the white background left inside an icon (a trophy's handles, a padlock's shackle), which BiRefNet
    takes for part of the drawing: a patch of near-pure white walled in by the drawing's dark outline. A white
    highlight borders lighter colours, so it stays. The edge round a hole is unmixed from the white. Returns the icon
    and how many holes it opened."""
    out = rgba.astype(np.float32).copy()
    rgb, alpha = out[..., :3], out[..., 3]
    white = (rgb.min(axis=2) >= HOLE_WHITE) & (alpha > 0)
    labels, n = ndimage.label(white)
    opened = 0
    for i in range(1, n + 1):
        patch = labels == i
        if patch.sum() < HOLE_AREA:
            continue
        ring = ndimage.binary_dilation(patch, iterations=3) & ~patch & (alpha > 128)
        if not ring.any() or np.median(rgb[ring].mean(axis=1)) > HOLE_WALL:
            continue
        band = ndimage.binary_dilation(patch, iterations=2) & ~patch
        a = np.clip((255 - rgb[band].min(axis=1)) / 120, 0, 1)
        rgb[band] = np.clip((rgb[band] - (1 - a[:, None]) * 255) / np.maximum(a[:, None], 1e-3), 0, 255)
        alpha[band] = np.minimum(alpha[band], a * 255)
        alpha[patch] = 0
        opened += 1
    return out.round().astype(np.uint8), opened


def fringe(rgba: np.ndarray) -> float:
    """How much lighter the half-transparent edge is than the solid outline nearest to each of its pixels (0 to 255);
    0 once defringed, so running it again changes nothing."""
    alpha = rgba[..., 3]
    edge = (alpha > 20) & (alpha < 235)
    solid = alpha >= 250
    if not edge.any() or not solid.any():
        return 0.0
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    rgb = rgba[..., :3].astype(np.float32)
    return float((rgb[edge] - rgb[iy[edge], ix[edge]]).mean())


def defringe(rgba: np.ndarray) -> np.ndarray:
    """Gives the half-transparent edge the colour of the solid outline nearest to it and tightens it by half a
    pixel, which takes off a light rim the background left there (an icon cut before the edge was unmixed)."""
    out = rgba.astype(np.float32).copy()
    alpha = out[..., 3]
    solid = alpha >= 250
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    edge = alpha < 250
    out[..., :3][edge] = out[..., :3][iy[edge], ix[edge]]
    out[..., 3] = np.where(edge, np.clip((alpha - DEFRINGE_CHOKE) / (250 - DEFRINGE_CHOKE), 0, 1) * 250, alpha)
    return out.round().astype(np.uint8)


def holes(paths: list[Path]):
    """Opens the holes of icons already cut and takes off a light rim, in place."""
    for path in paths:
        rgba, opened = open_holes(np.asarray(Image.open(path).convert("RGBA")))
        rim = fringe(rgba)
        if rim > FRINGE:
            rgba = defringe(rgba)
        if opened or rim > FRINGE:
            Image.fromarray(rgba).save(path)
            print(f"{path}: opened {opened}, rim {rim:.0f}{' taken off' if rim > FRINGE else ''}")


def find_icons(alpha: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Bounds (x0, y0, x1, y1) of each icon in reading order."""
    solid = ndimage.binary_dilation(alpha > 0.5, iterations=JOIN)
    labels, _ = ndimage.label(solid)
    boxes = []
    for found in ndimage.find_objects(labels):
        ys, xs = found
        boxes.append((xs.start + JOIN, ys.start + JOIN, xs.stop - JOIN, ys.stop - JOIN))
    largest = max((b[2] - b[0]) * (b[3] - b[1]) for b in boxes)
    boxes = [b for b in boxes if (b[2] - b[0]) * (b[3] - b[1]) >= SPECK * largest]
    # Rows: icons whose centres lie within half a typical height of each other.
    height = np.median([b[3] - b[1] for b in boxes])
    boxes.sort(key=lambda b: (b[1] + b[3]) / 2)
    rows: list[list] = []
    for b in boxes:
        centre = (b[1] + b[3]) / 2
        if rows and abs(centre - np.mean([(r[1] + r[3]) / 2 for r in rows[-1]])) < height / 2:
            rows[-1].append(b)
        else:
            rows.append([b])
    return [b for row in rows for b in sorted(row, key=lambda b: b[0])]


def cut(sheet: Path, out: Path, names: list[str], bottom: bool):
    image = Image.open(sheet).convert("RGB")
    rgb = np.asarray(image, dtype=np.float32)
    h, w = rgb.shape[:2]
    coarse = mask(image)
    back = background_colour(rgb, coarse)
    icons = find_icons(coarse)
    print(f"{sheet.name}: {len(icons)} icons, background {back.round()}")
    if len([n for n in names]) > len(icons):
        sys.exit(f"{len(names)} names for {len(icons)} icons")
    out.mkdir(parents=True, exist_ok=True)
    for (x0, y0, x1, y1), name in zip(icons, names):
        if name == "-":
            continue
        # The icon alone with room round it, masked again for a finer edge.
        pad = int(max(x1 - x0, y1 - y0) * 0.15)
        px0, py0, px1, py1 = max(0, x0 - pad), max(0, y0 - pad), min(w, x1 + pad), min(h, y1 + pad)
        piece = rgb[py0:py1, px0:px1]
        alpha = mask(Image.fromarray(piece.astype(np.uint8)))
        # Only this icon: drop what belongs to a neighbour reaching into the padding.
        labels, n = ndimage.label(ndimage.binary_dilation(alpha > 0.5, iterations=JOIN))
        if n > 1:
            centre = labels[(y0 + y1) // 2 - py0, (x0 + x1) // 2 - px0]
            if centre:
                alpha = np.where(labels == centre, alpha, 0)
        alpha = np.clip((alpha - CHOKE) / (1 - CHOKE), 0, 1)
        colour = decontaminate(piece, alpha, back)
        rgba = np.dstack([colour, alpha * 255])

        ys, xs = np.nonzero(alpha > 0.5)
        bx0, bx1, by0, by1 = xs.min(), xs.max(), ys.min(), ys.max()
        side = int(round(max(bx1 - bx0, by1 - by0) * (1 + 2 * MARGIN)))
        cx = (bx0 + bx1) / 2
        cy = by1 + side * MARGIN - side / 2 if bottom else (by0 + by1) / 2
        sx, sy = int(round(cx - side / 2)), int(round(cy - side / 2))
        square = np.zeros((side, side, 4), dtype=np.float32)
        # Paste the icon into the square, clipped to the piece.
        ax0, ay0 = max(0, sx), max(0, sy)
        ax1, ay1 = min(rgba.shape[1], sx + side), min(rgba.shape[0], sy + side)
        square[ay0 - sy : ay1 - sy, ax0 - sx : ax1 - sx] = rgba[ay0:ay1, ax0:ax1]
        icon, _ = open_holes(premultiplied_resize(square, SIZE))
        if fringe(icon) > FRINGE:
            icon = defringe(icon)
        Image.fromarray(icon).save(out / f"{name}.png")
        print("wrote", out / f"{name}.png")


def check(paths: list[Path], target: Path):
    """Each icon on a dark and a light ground, side by side."""
    cell = 160
    sheet = Image.new("RGB", (cell * len(paths), cell * 2))
    for i, path in enumerate(paths):
        icon = Image.open(path).convert("RGBA").resize((cell, cell), Image.LANCZOS)
        for row, ground in enumerate(((30, 20, 16), (236, 228, 214))):
            tile = Image.new("RGBA", (cell, cell), ground + (255,))
            tile.alpha_composite(icon)
            sheet.paste(tile.convert("RGB"), (i * cell, row * cell))
    sheet.save(target)
    print("wrote", target)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--check":
        check([Path(p) for p in args[2:]], Path(args[1]))
    elif args and args[0] == "--holes":
        holes([Path(p) for p in args[1:]])
    else:
        bottom = "--bottom" in args
        args = [a for a in args if a != "--bottom"]
        cut(Path(args[0]), Path(args[1]), args[2:], bottom)
