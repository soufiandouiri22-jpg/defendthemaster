#!/usr/bin/env python3
"""Prints the keyframe markers of a pack's clips (a KeyframeSequence in binary .rbxm), with their times. A KitsBlox
pack's "RA_Sound" markers name its sound cues, but most of them are footsteps, and an effect's cue is where its
recording starts, not where the shot or swing in it falls: a kit's `Hit` or `Releases` come from the sound add-on's
recordings (Sound Map's "Effect" cues plus where the crack sits in the recording), checked against the clip's motion.
Reads the binary format itself (LZ4 chunks), nothing to install.

    python3 Tools/clip_markers.py Gunslinger RA-GSL-033 [RA-GSL-045 ...]
"""

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def lz4_block(src: bytes) -> bytes:
    out = bytearray()
    i = 0
    while i < len(src):
        token = src[i]
        i += 1
        literals = token >> 4
        if literals == 15:
            while True:
                b = src[i]
                i += 1
                literals += b
                if b != 255:
                    break
        out += src[i : i + literals]
        i += literals
        if i >= len(src):
            break
        offset = src[i] | (src[i + 1] << 8)
        i += 2
        length = token & 15
        if length == 15:
            while True:
                b = src[i]
                i += 1
                length += b
                if b != 255:
                    break
        start = len(out) - offset
        for k in range(length + 4):
            out.append(out[start + k])
    return bytes(out)


def interleaved(data: bytes, count: int) -> list[int]:
    return [int.from_bytes(bytes(data[j * count + i] for j in range(4)), "big") for i in range(count)]


def referents(data: bytes, count: int) -> list[int]:
    out, total = [], 0
    for v in interleaved(data, count):
        total += (v >> 1) ^ -(v & 1)
        out.append(total)
    return out


def roblox_float(x: int) -> float:
    x = ((x >> 1) | (x << 31)) & 0xFFFFFFFF
    return struct.unpack(">f", x.to_bytes(4, "big"))[0]


def markers(path: Path) -> list[tuple[float, str, str]]:
    raw = path.read_bytes()
    pos = 32
    classes: dict[int, tuple[str, list[int]]] = {}
    props: dict[int, dict] = {}
    parents: dict[int, int] = {}
    while pos < len(raw):
        name = raw[pos : pos + 4]
        packed, size = struct.unpack("<II", raw[pos + 4 : pos + 12])
        pos += 16
        data = raw[pos : pos + size] if packed == 0 else lz4_block(raw[pos : pos + packed])
        pos += size if packed == 0 else packed
        if name == b"INST":
            cid, n = struct.unpack("<II", data[0:8])
            p = 9 + n
            count = struct.unpack("<I", data[p : p + 4])[0]
            classes[cid] = (data[8 : 8 + n].decode(), referents(data[p + 4 : p + 4 + count * 4], count))
        elif name == b"PROP":
            cid, n = struct.unpack("<II", data[0:8])
            prop, kind, body = data[8 : 8 + n].decode(), data[8 + n], data[9 + n :]
            ids = classes[cid][1]
            if kind == 1:
                values, q = [], 0
                for _ in ids:
                    length = struct.unpack("<I", body[q : q + 4])[0]
                    values.append(body[q + 4 : q + 4 + length].decode("utf-8", "replace"))
                    q += 4 + length
            elif kind == 4:
                values = [roblox_float(v) for v in interleaved(body, len(ids))]
            else:
                continue
            for r, v in zip(ids, values):
                props.setdefault(r, {})[prop] = v
        elif name == b"PRNT":
            count = struct.unpack("<I", data[1:5])[0]
            children = referents(data[5 : 5 + count * 4], count)
            parents.update(zip(children, referents(data[5 + count * 4 : 5 + count * 8], count)))
        elif name == b"END\0":
            break
    found = []
    for cname, ids in classes.values():
        if cname == "KeyframeMarker":
            for r in ids:
                found.append((props.get(parents.get(r, -1), {}).get("Time", 0.0), props[r].get("Name", ""),
                              props[r].get("Value", "")))
    return sorted(found)


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    folder = ROOT / "Vendor" / sys.argv[1] / "Animations" / "Individual Animations"
    for clip in sys.argv[2:]:
        files = sorted(folder.rglob(f"{clip} *.rbxm"))
        if not files:
            print(clip, "not found")
            continue
        print(files[0].stem)
        for time, name, value in markers(files[0]):
            print(f"  {time:.3f}  {name}  {value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
