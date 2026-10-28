# Makes the blue team copy of a red Meshy GLB: only the crimson pixels of its base colour turn royal blue, so gold,
# stone and wood stay exactly the red piece's. Geometry, UVs and everything else in the GLB are copied unchanged.
# python3 Tools/team_recolor.py <red.glb> <blue.glb> [preview.png]
# python3 Tools/team_recolor.py --image <red.png> <blue.png> [--no-skin]   (a portrait or clothing template; a
# painting's skin stays, unless --no-skin: for one without skin, whose light reds are lit crystal or glow)
import io
import json
import struct
import sys

import numpy as np
from PIL import Image

BLUE_HUE = 222 / 360
RED_HUES = (338 / 360, 14 / 360)
FEATHER = 6 / 360
MIN_SAT = 0.30


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2, path
    chunks, offset = [], 12
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunks.append((kind, data[offset + 8 : offset + 8 + length]))
        offset += 8 + length
    gltf = json.loads(chunks[0][1].rstrip(b" \x00"))
    return gltf, chunks[1][1]


def write_glb(path, gltf, binary):
    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    binary += b"\x00" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(text), 0x4E4F534A) + text)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def recolor(image, spare_skin=False):
    hsv = np.asarray(image.convert("HSV")).astype(np.float32) / 255
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    lo, hi = RED_HUES
    distance = np.where((h >= lo) | (h <= hi), 0, np.minimum(np.abs(h - lo), np.abs(h - hi)))
    weight = np.clip(1 - distance / FEATHER, 0, 1) * np.clip((s - MIN_SAT) / 0.15, 0, 1)
    if spare_skin:
        # A painting's lit skin is a light, soft orange-red: it keeps its colour.
        skin = np.clip((v - 0.45) / 0.1, 0, 1) * np.clip((0.62 - s) / 0.08, 0, 1) * ((h <= 45 / 360) | (h >= 350 / 360))
        weight = weight * (1 - skin)
    out = hsv.copy()
    out[..., 0] = np.where(weight > 0, BLUE_HUE, h)
    rgb_old = np.asarray(image.convert("RGB")).astype(np.float32)
    rgb_new = np.asarray(Image.fromarray((out * 255).round().astype(np.uint8), "HSV").convert("RGB")).astype(np.float32)
    mixed = rgb_old * (1 - weight[..., None]) + rgb_new * weight[..., None]
    return Image.fromarray(mixed.round().astype(np.uint8), "RGB"), weight


def main():
    if sys.argv[1] == "--image":
        source, target = sys.argv[2:4]
        image = Image.open(source)
        blue, weight = recolor(image, spare_skin="--no-skin" not in sys.argv[4:])
        if image.mode == "RGBA":
            blue = blue.convert("RGBA")
            blue.putalpha(image.getchannel("A"))
        blue.save(target)
        print(f"{target}: {int((weight > 0.5).sum())} pixels turned blue")
        return
    source, target = sys.argv[1:3]
    gltf, binary = read_glb(source)
    material = gltf["materials"][0]
    index = gltf["textures"][material["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]
    old_view = gltf["bufferViews"][gltf["images"][index]["bufferView"]]
    start = old_view.get("byteOffset", 0)
    image = Image.open(io.BytesIO(binary[start : start + old_view["byteLength"]]))
    blue, weight = recolor(image)
    if len(sys.argv) > 3:
        blue.save(sys.argv[3])
    encoded = io.BytesIO()
    blue.save(encoded, "PNG")
    png = encoded.getvalue()
    png += b"\x00" * (-len(png) % 4)
    end = start + old_view["byteLength"]
    end += -end % 4
    shift = start + len(png) - end
    binary = binary[:start] + png + binary[end:]
    for view in gltf["bufferViews"]:
        if view is not old_view and view.get("byteOffset", 0) >= end:
            view["byteOffset"] = view.get("byteOffset", 0) + shift
    old_view["byteLength"] = len(png)
    gltf["images"][index]["mimeType"] = "image/png"
    gltf["buffers"][0]["byteLength"] = len(binary)
    write_glb(target, gltf, bytes(binary))
    print(f"{target}: {int((weight > 0.5).sum())} pixels turned blue")


if __name__ == "__main__":
    main()
