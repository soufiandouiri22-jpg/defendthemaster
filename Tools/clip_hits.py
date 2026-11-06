#!/usr/bin/env python3
"""Finds when a KeyframeSequence pack's weapon strikes in a clip: the moments its tip moves fastest, worked out on the
pack's own rig (its joints and the weapon's joint as Tools/keyframe_pack.py has them), for a kit's hit times.

    python3 Tools/clip_hits.py GreatswordKnight RA-GSK-043 [tip]

`tip` is how far along the weapon's long axis (its Y, from the part's centre) the tip lies; by default half its
reference length. Prints the tip's speed peaks (time, studs a second, and the tip's height and reach from the root).
"""

import sys
import xml.etree.ElementTree as ET

from keyframe_pack import JOINT_ORDER, PACKS, ROOT, cframe, props, rig_joints

# Half the length of each pack's weapon (Weapon Attachment.json's reference size, its long axis Y).
TIPS = {"GreatswordKnight": 11.0402 / 2, "Elementalist": 6.366 / 2, "TricksterCaster": 4.865 / 2, "Wildguard": 4.3815 / 2, "ArenaFighter": 3.204 / 2, "Lancer": 11.6208 / 2}


def mul(a: list[float], b: list[float]) -> list[float]:
    """Two CFrames (x, y, z, then the rotation's rows) multiplied."""
    ra = [a[3:6], a[6:9], a[9:12]]
    rb = [b[3:6], b[6:9], b[9:12]]
    rot = [[sum(ra[i][k] * rb[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    pos = [a[i] + sum(ra[i][k] * b[k] for k in range(3)) for i in range(3)]
    return pos + rot[0] + rot[1] + rot[2]


def inv(a: list[float]) -> list[float]:
    r = [a[3:6], a[6:9], a[9:12]]
    t = [[r[j][i] for j in range(3)] for i in range(3)]
    pos = [-sum(t[i][k] * a[k] for k in range(3)) for i in range(3)]
    return pos + t[0] + t[1] + t[2]


def point(a: list[float], p: list[float]) -> list[float]:
    r = [a[3:6], a[6:9], a[9:12]]
    return [a[i] + sum(r[i][k] * p[k] for k in range(3)) for i in range(3)]


IDENTITY = [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]


def tip_path(name: str, clip_id: str, tip: float) -> tuple[str, list[tuple[float, list[float]]]]:
    """The clip's name, and where the weapon's tip is (from the root part) at each of its keyframes."""
    pack = PACKS[name]
    source = ROOT / "Vendor" / name / "Animations"
    path = next((source / pack["clips"]).rglob(f"{clip_id} *.rbxmx"), None)
    if not path:
        sys.exit(f"no clip {clip_id} in {source / pack['clips']}")

    joints = {j["name"]: j for j in rig_joints(source / "Included Rig.rbxmx")}
    weapon = pack["weapon"]
    chain = [joints[n] for n in JOINT_ORDER] + [
        {"part0": weapon["parent"], "part1": weapon["name"], "c0": weapon["c0"], "c1": weapon["c1"]}
    ]

    sequence = ET.parse(path).getroot().find("Item")
    frames = []
    last: dict[str, list[float]] = {}
    keyframes = []
    for keyframe in sequence.findall("Item[@class='Keyframe']"):
        poses = {}

        def walk(item):
            for pose in item.findall("Item[@class='Pose']"):
                p = props(pose)
                poses[p["Name"].text] = cframe(p["CFrame"])
                walk(pose)

        walk(keyframe)
        keyframes.append((float(props(keyframe)["Time"].text), poses))
    keyframes.sort(key=lambda k: k[0])
    for time, poses in keyframes:
        last.update(poses)
        world = {"HumanoidRootPart": IDENTITY}
        for j in chain:
            transform = last.get(j["part1"], IDENTITY)
            world[j["part1"]] = mul(mul(mul(world[j["part0"]], j["c0"]), transform), inv(j["c1"]))
        frames.append((time, point(world[weapon["name"]], [0, tip, 0])))
    return path.stem[len(clip_id) + 1 :], frames


def main() -> int:
    if len(sys.argv) not in (3, 4) or sys.argv[1] not in PACKS:
        sys.exit(__doc__)
    name, clip_id = sys.argv[1], sys.argv[2]
    tip = float(sys.argv[3]) if len(sys.argv) == 4 else TIPS[name]
    title, frames = tip_path(name, clip_id, tip)

    speeds = []
    for (t0, a), (t1, b) in zip(frames, frames[1:]):
        if t1 > t0:
            d = sum((b[i] - a[i]) ** 2 for i in range(3)) ** 0.5
            speeds.append(((t0 + t1) / 2, d / (t1 - t0), b))
    top = max(s for _, s, _ in speeds)
    print(f"{clip_id} ({title}): {frames[-1][0]:.2f} s, fastest {top:.0f} studs/s")
    for i, (t, s, p) in enumerate(speeds):
        before = speeds[i - 1][1] if i > 0 else 0
        after = speeds[i + 1][1] if i + 1 < len(speeds) else 0
        if s >= before and s >= after and s >= top * 0.45:
            reach = (p[0] ** 2 + p[2] ** 2) ** 0.5
            print(f"  {t:.2f} s  {s:5.0f} studs/s  tip height {p[1]:+.1f}, reach {reach:.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
