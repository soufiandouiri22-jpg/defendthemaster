#!/usr/bin/env python3
"""Turns a bought animation pack that comes as KeyframeSequences (the Elementalist, Docs/Third_Party.md) into what
Shared.Motion plays: a ComponentPlayer as the newer packs have, with the pack rig's joints in its Configuration, its
clips as keyframe data (Data) and its player Shared.KeyframePlayer.

    python3 Tools/keyframe_pack.py Elementalist|GreatswordKnight

Writes Vendor/<pack>/Build/ (kept out of git with the rest of Vendor/), which Rojo serves as ReplicatedStorage.<pack>
(default.project.json). The weapon lives in the place, in ReplicatedStorage.<pack>.Components (Rojo cannot set a
MeshPart's mesh): its MeshPart from the model uploaded by Tools/upload_model.py, with a Motor6D "ComponentBinding".
"""

import base64
import json
import pathlib
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Per pack: its clips' folder and the weapon (its part's name, the joint it hangs from and that joint's frames, as the
# pack's "Attach equipment" script sets them).
PACKS = {
    "Elementalist": {
        "clips": "Individual Animations/With Equipment",
        "weapon": {
            "name": "Staff",
            "parent": "RightHand",
            "c0": [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1],
            "c1": [0, 1.72821, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1],
        },
    },
    # The Greatsword Knight's clips lie in subfolders per kind; its sword hangs from the right hand ("Attach
    # Greatsword.lua", Weapon Attachment.json).
    "GreatswordKnight": {
        "clips": "Individual Animations/with-greatsword",
        "weapon": {
            "name": "Greatsword",
            "parent": "RightHand",
            "c0": [0, 0, 0, -1, 0, 0, 0, 1, 0, 0, 0, -1],
            "c1": [0, -2.49969, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1],
        },
    },
}

# The pack rig's joints, each after the one it hangs from.
JOINT_ORDER = [
    "Root", "Waist", "Neck",
    "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
    "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle",
]
CF_KEYS = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]


def cframe(node) -> list[float]:
    return [float(node.find(k).text) for k in CF_KEYS]


def quaternion(m: list[float]) -> list[float]:
    """The rotation of a CFrame's 12 numbers as x, y, z, w."""
    r00, r01, r02, r10, r11, r12, r20, r21, r22 = m[3:]
    trace = r00 + r11 + r22
    if trace > 0:
        s = (trace + 1) ** 0.5 * 2
        w, x, y, z = s / 4, (r21 - r12) / s, (r02 - r20) / s, (r10 - r01) / s
    elif r00 > r11 and r00 > r22:
        s = (1 + r00 - r11 - r22) ** 0.5 * 2
        w, x, y, z = (r21 - r12) / s, s / 4, (r01 + r10) / s, (r02 + r20) / s
    elif r11 > r22:
        s = (1 + r11 - r00 - r22) ** 0.5 * 2
        w, x, y, z = (r02 - r20) / s, (r01 + r10) / s, s / 4, (r12 + r21) / s
    else:
        s = (1 + r22 - r00 - r11) ** 0.5 * 2
        w, x, y, z = (r10 - r01) / s, (r02 + r20) / s, (r12 + r21) / s, s / 4
    return [x, y, z, w]


def floats(values: list[float]) -> str:
    """Numbers as little-endian float32s in base64: one string constant instead of thousands, which Luau's compiler
    cannot hold in one module."""
    return base64.b64encode(struct.pack(f"<{len(values)}f", *values)).decode()


def props(item) -> dict:
    found = {}
    for p in item.find("Properties"):
        found[p.get("name")] = p
    return found


def rig_joints(path: pathlib.Path) -> list[dict]:
    root = ET.parse(path).getroot()
    names = {}
    for item in root.iter("Item"):
        p = props(item)
        if "Name" in p:
            names[item.get("referent")] = p["Name"].text
    joints = {}
    for item in root.iter("Item"):
        if item.get("class") != "Motor6D":
            continue
        p = props(item)
        joints[p["Name"].text] = {
            "name": p["Name"].text,
            "part0": names[p["Part0"].text],
            "part1": names[p["Part1"].text],
            "c0": cframe(p["C0"]),
            "c1": cframe(p["C1"]),
        }
    return [joints[name] for name in JOINT_ORDER]


def clip(path: pathlib.Path, parts: set[str]) -> tuple[str, dict]:
    sequence = ET.parse(path).getroot().find("Item")
    sp = props(sequence)
    name = sp["Name"].text
    keyframes = []
    markers = []
    for keyframe in sequence.findall("Item[@class='Keyframe']"):
        time = float(props(keyframe)["Time"].text)
        poses = {}

        def walk(item):
            for pose in item.findall("Item[@class='Pose']"):
                p = props(pose)
                part = p["Name"].text
                style = int(p["EasingStyle"].text) if "EasingStyle" in p else 0
                if part in parts:
                    if style not in (0, 1):
                        raise SystemExit(f"{name}: {part} eases with style {style}, only linear and constant are read")
                    poses[part] = (cframe(p["CFrame"]), style)
                walk(pose)

        walk(keyframe)
        for marker in keyframe.findall("Item[@class='KeyframeMarker']"):
            mp = props(marker)
            markers.append({"Time": time, "Name": mp["Name"].text, "Value": (mp.get("Value").text or "") if mp.get("Value") is not None else ""})
        keyframes.append((time, poses))
    keyframes.sort(key=lambda k: k[0])
    times = [k[0] for k in keyframes]
    tracks = {}
    for part in sorted(parts):
        keyed = [(t, poses[part]) for t, poses in keyframes if part in poses]
        if not keyed:
            continue
        values = []
        constant = []
        for t in times:
            # A keyframe without this part's pose takes the nearest earlier one (or the first).
            before = [k for k in keyed if k[0] <= t + 1e-6]
            frame, style = (before[-1] if before else keyed[0])[1]
            values.extend(round(v, 5) for v in frame[:3] + quaternion(frame))
            constant.append(style == 1)
        tracks[part] = {"values": floats(values), "constant": constant if any(constant) else None}
    loop = sp["Loop"].text == "true"
    # The Elementalist names its sequences "<id> <name>"; the Greatsword Knight only its files.
    clip_id = path.stem.split(" ")[0]
    if name.startswith(clip_id + " "):
        name = name[len(clip_id) + 1 :]
    return clip_id, {
        "meta": {
            "id": clip_id,
            "name": name,
            "duration": times[-1] if times else 0,
            "loop": loop,
            "markers": markers,
        },
        "times": floats(times),
        "tracks": tracks,
    }


def lua(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "nil"
    if isinstance(value, (int, float)):
        text = repr(round(value, 5))
        return text[:-2] if text.endswith(".0") else text
    if isinstance(value, str):
        # As UTF-8: Luau has no \uXXXX escapes (the clips' names hold dashes).
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{" + ",".join(lua(v) for v in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join(f"[{json.dumps(k)}]={lua(v)}" for k, v in value.items()) + "}"
    raise TypeError(type(value))


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in PACKS:
        sys.exit(__doc__)
    name = sys.argv[1]
    pack = PACKS[name]
    source = ROOT / "Vendor" / name / "Animations"
    out = ROOT / "Vendor" / name / "Build"
    player = out / "ComponentPlayer"
    player.mkdir(parents=True, exist_ok=True)

    joints = rig_joints(source / "Included Rig.rbxmx")
    weapon = pack["weapon"]
    config = {
        "product": name,
        "body_joints": joints,
        "weapon": {k: weapon[k] for k in ("name", "parent", "c0", "c1")},
    }
    (player / "Configuration.txt").write_text(json.dumps(config))

    parts = {j["part1"] for j in joints} | {weapon["name"]}
    clips = {}
    for path in sorted((source / pack["clips"]).rglob("*.rbxmx")):
        clip_id, data = clip(path, parts)
        clips[clip_id] = data
    (player / "Data.luau").write_text(encoding="utf-8", data=
        "-- Generated by Tools/keyframe_pack.py from the pack's KeyframeSequences: per clip its keyframes' times and\n"
        "-- per part a position and a rotation (x, y, z, qx, qy, qz, qw) at each of them, as float32s in base64.\n"
        "return " + lua(clips) + "\n"
    )
    (player / "init.luau").write_text(
        "-- Generated by Tools/keyframe_pack.py: plays this pack's keyframe clips (Shared.KeyframePlayer).\n"
        'return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("KeyframePlayer"))(script)\n'
    )
    size = (player / "Data.luau").stat().st_size
    print(f"{name}: {len(clips)} clips, {len(joints)} joints, Data {size // 1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
