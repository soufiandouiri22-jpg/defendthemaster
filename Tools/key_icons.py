"""Keys an icon drawn alone on a flat key colour (pure magenta, or green for purple icons; Meshy image-to-image from the
icon on white, Art/Icons/keyed) into a square PNG with a clean transparent edge, and checks it.

    python3 Tools/key_icons.py <keyed.png> <out.png> [--bottom] [--glow] [--like <old.png>]
    python3 Tools/key_icons.py --check <out.png> [<out.png> ...]

Cutting icons out of white (Tools/cut_icons.py) could never be exact: silver and shine are as light as the
background, so a light rim, white left in holes and bits of the next icon on the sheet came along. A key colour that
appears nowhere in the drawing leaves no doubt:
- the key is the median of the picture's border; a pixel this far from it is drawing (SOLID), this close background;
- every pixel in between takes the colour of the nearest solid pixel, and its alpha is how far it lies from the key
  towards that colour, so no key colour and no rim can be left on the edge;
- background walled in by the drawing is keyed like the rest, and anything not joined to the drawing is dropped;
- the icon is cut at its bounds into a square with a margin, centred (or with --bottom standing on its foot; or with
  --like as large and in the same place as the icon it replaces), and scaled down premultiplied.

--check fails an icon that still has a rim lighter than its outline, key colour on its edge, loose bits, or drawing
on the border of its square.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

SIZE = 256
MARGIN = 0.06
# Distance from the key (RGB, 0 to 441) beyond which a pixel is solid drawing, and under which it is background.
SOLID = 150
CLEAR = 45
# Key colour walled in by the drawing is a hole when it covers this share of the picture; smaller is a reflection.
HOLE = 0.0015
# How many pixels wide the edge between drawing and background is taken, and with --glow (a soft glow or smoke round
# the drawing) how far out it may reach.
EDGE = 3
GLOW_EDGE = 60
# How much of the key's tint is taken out of the drawing (1: all of it). Off for icons that use the key's hue.
DESPILL = 1.0
# Tints this close to the key's hue (cosine) count as its reflection.
SPILL_HUE = 0.94
# Loose pieces smaller than this share of the drawing are specks and dropped; larger ones (a flame, a spark) stay.
SPECK = 0.002
# --check: an edge this much lighter than its outline is a rim; this much key colour on the edge is spill.
RIM = 12
SPILL = 0.02
# --check: the outermost OUTER pixels of the shape brighter than LIGHT in patches of LIGHT_PATCH pixels are a rim.
OUTER = 1.5
LIGHT = 200
LIGHT_PATCH = 4


def key_colour(rgb: np.ndarray) -> np.ndarray:
    border = np.concatenate([rgb[:4].reshape(-1, 3), rgb[-4:].reshape(-1, 3), rgb[:, :4].reshape(-1, 3),
                             rgb[:, -4:].reshape(-1, 3)])
    return np.median(border, axis=0)


def key(rgb: np.ndarray, glow: bool = False) -> np.ndarray:
    """RGBA of `rgb` keyed against the colour of its border."""
    k = key_colour(rgb)
    distance = np.linalg.norm(rgb - k, axis=2)
    eight = np.ones((3, 3))
    # Background is the key colour reached from the border, and patches of it walled in by the drawing that are too
    # large to be a reflection of the key on metal or glass.
    clear = distance < CLEAR
    labels, n = ndimage.label(clear, structure=eight)
    sizes = ndimage.sum(np.ones_like(distance), labels, range(1, n + 1))
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    hole = HOLE * distance.size
    background = np.isin(labels, [i + 1 for i in range(n) if i + 1 in border or sizes[i] >= hole])
    background = ndimage.binary_dilation(background, iterations=1) & (distance < SOLID)
    drawing = ~background
    labels, n = ndimage.label(drawing, structure=eight)
    if n == 0:
        sys.exit("nothing drawn on the key colour")
    sizes = ndimage.sum(np.ones_like(distance), labels, range(1, n + 1))
    drawing = np.isin(labels, 1 + np.nonzero(sizes >= SPECK * sizes.max())[0])
    # The edge: drawn pixels next to the background, part drawing and part key colour.
    reach = GLOW_EDGE if glow else EDGE
    inside = drawing & (distance >= SOLID)
    edge = drawing & ~inside & ndimage.binary_dilation(background, iterations=reach)
    if glow:
        # A glow or smoke has no colour of its own to compare with: each pixel is the most transparent mix of the key
        # and a real colour that gives it.
        span = np.where(rgb > k, (255 - k), k)
        need = np.abs(rgb - k) / np.maximum(span, 1e-3)
        alpha = np.clip(need.max(axis=2), 0, 1)
        unmixed = k + (rgb - k) / np.maximum(alpha[..., None], 1e-3)
        alpha = np.where(edge, alpha, drawing.astype(np.float32))
        colour = np.where(edge[..., None], np.clip(unmixed, 0, 255), despill(rgb, k))
        return np.dstack([colour, alpha * 255]).astype(np.float32)
    # A hard edge: each pixel takes the colour of the nearest pixel inside, and its alpha is how far it lies from the
    # key towards that colour.
    _, (iy, ix) = ndimage.distance_transform_edt(~inside, return_indices=True)
    nearest = rgb[iy, ix]
    towards = nearest - k
    alpha = np.einsum("ijk,ijk->ij", rgb - k, towards) / np.maximum(np.einsum("ijk,ijk->ij", towards, towards), 1e-3)
    alpha = np.where(edge, np.clip(alpha, 0, 1), drawing.astype(np.float32))
    colour = np.where(edge[..., None], nearest, despill(rgb, k))
    return np.dstack([colour, alpha * 255]).astype(np.float32)


def despill(rgb: np.ndarray, k: np.ndarray) -> np.ndarray:
    """Takes the key's tint out of reflections on metal: a pixel whose tint has the key's own hue is moved back to its
    neutral grey. Other hues (the red of a ribbon next to magenta) keep their colour."""
    grey = k.mean()
    tint = (k - grey) / np.linalg.norm(k - grey)
    chroma = rgb - rgb.mean(axis=2, keepdims=True)
    along = np.einsum("ijk,k->ij", chroma, tint)
    cosine = along / np.maximum(np.linalg.norm(chroma, axis=2), 1e-3)
    weight = np.clip((cosine - SPILL_HUE) / (1 - SPILL_HUE), 0, 1) * DESPILL
    return np.clip(rgb - (np.clip(along, 0, None) * weight)[..., None] * tint, 0, 255)


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


def bleed(rgba: np.ndarray) -> np.ndarray:
    """The colour of the nearest opaque pixel under every transparent and half-transparent one, so scaling the icon
    down in the game (mipmaps) blends in nothing but the drawing's own edge."""
    out = rgba.copy()
    solid = rgba[..., 3] >= 250
    if solid.any():
        _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
        edge = ~solid
        out[..., :3][edge] = rgba[..., :3][iy[edge], ix[edge]]
    return out


def bounds(alpha: np.ndarray) -> tuple[float, float, float]:
    """Centre x, centre y and size (the longer side) of what is drawn."""
    ys, xs = np.nonzero(alpha > 8)
    return (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2, float(max(xs.max() - xs.min(), ys.max() - ys.min()))


def square(rgba: np.ndarray, bottom: bool, like: Path | None = None) -> np.ndarray:
    cx, cy, size = bounds(rgba[..., 3])
    if like:
        # As large and in the same place in its square as the icon it replaces.
        old = np.asarray(Image.open(like).convert("RGBA"))
        ox, oy, osize = bounds(old[..., 3])
        side = int(round(size * old.shape[0] / osize))
        sx, sy = int(round(cx - ox * side / old.shape[0])), int(round(cy - oy * side / old.shape[0]))
    else:
        side = int(round(size * (1 + 2 * MARGIN)))
        ys = np.nonzero(rgba[..., 3] > 8)[0]
        if bottom:
            cy = ys.max() + side * MARGIN - side / 2
        sx, sy = int(round(cx - side / 2)), int(round(cy - side / 2))
    out = np.zeros((side, side, 4), dtype=np.float32)
    ax0, ay0 = max(0, sx), max(0, sy)
    ax1, ay1 = min(rgba.shape[1], sx + side), min(rgba.shape[0], sy + side)
    out[ay0 - sy : ay1 - sy, ax0 - sx : ax1 - sx] = rgba[ay0:ay1, ax0:ax1]
    return out


def make(source: Path, target: Path, bottom: bool, like: Path | None = None, glow: bool = False):
    rgb = np.asarray(Image.open(source).convert("RGB"), dtype=np.float32)
    icon = bleed(premultiplied_resize(square(key(rgb, glow), bottom, like), SIZE))
    target.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(icon).save(target)
    problems = check_one(icon, glow)
    print(f"{target}: {'PASS' if not problems else 'FAIL ' + ', '.join(problems)}")


def check_one(rgba: np.ndarray, glow: bool = False) -> list[str]:
    problems = []
    alpha = rgba[..., 3].astype(np.float32)
    rgb = rgba[..., :3].astype(np.float32)
    solid = alpha >= 250
    edge = (alpha > 20) & (alpha < 250)
    if edge.any() and solid.any():
        _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
        rim = float((rgb[edge] - rgb[iy[edge], ix[edge]]).mean())
        if rim > RIM:
            problems.append(f"rim {rim:.0f}")
        r, g, b = rgb[edge].T
        spill = float(np.mean((np.minimum(r, b) - g > 60) & (r > 150) & (b > 150)))
        if spill > SPILL:
            problems.append(f"magenta on the edge {spill:.2f}")
    # The drawings have a dark outline all round: a light patch on the outermost pixels is a rim left over (a glow is
    # meant to be light).
    shape = alpha > 128
    band = shape & (ndimage.distance_transform_edt(shape) <= OUTER)
    light = band & (rgb.max(axis=2) > LIGHT)
    if light.any() and not glow:
        patches, count = ndimage.label(light, structure=np.ones((3, 3)))
        sizes = ndimage.sum(np.ones_like(alpha), patches, range(1, count + 1))
        if (sizes >= LIGHT_PATCH).any():
            problems.append(f"light rim ({int((sizes >= LIGHT_PATCH).sum())} patches, largest {int(sizes.max())} px)")
    labels, n = ndimage.label(alpha > 10, structure=np.ones((3, 3)))
    if n > 1:
        sizes = ndimage.sum(np.ones_like(alpha), labels, range(1, n + 1))
        small = int(np.sum(sizes < SPECK * 4 * sizes.max()))
        if small:
            problems.append(f"{small} loose bits")
    if max(alpha[0].max(), alpha[-1].max(), alpha[:, 0].max(), alpha[:, -1].max()) > 8:
        problems.append("drawing on the border")
    return problems


def check(paths: list[Path]) -> bool:
    ok = True
    for path in paths:
        problems = check_one(np.asarray(Image.open(path).convert("RGBA")))
        ok &= not problems
        print(f"{path}: {'PASS' if not problems else 'FAIL ' + ', '.join(problems)}")
    return ok


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--check":
        sys.exit(0 if check([Path(p) for p in args[1:]]) else 1)
    bottom = "--bottom" in args
    glow = "--glow" in args
    args = [a for a in args if a not in ("--bottom", "--glow")]
    like = None
    if "--like" in args:
        at = args.index("--like")
        like = Path(args[at + 1])
        del args[at : at + 2]
    make(Path(args[0]), Path(args[1]), bottom, like, glow)
