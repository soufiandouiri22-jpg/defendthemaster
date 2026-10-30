#!/usr/bin/env python3
"""Puts a hero's or the Masters' sounds from their bought animation pack's sound add-on into the game
(Docs/Third_Party.md).

The pack's Sound Map.json says which recordings play at which moment of each clip. This takes the cues of the clips a
hero uses, joins every recording they need into one audio file (one Roblox upload: an account that is not ID-verified
may upload only 10 audio files a month) and writes `src/shared/PackSounds/<Pack>.luau`: the uploaded asset, where
each recording sits in it (played with Sound.PlaybackRegion) and the cues per clip.

    python3 Tools/hero_sounds.py build ShadowDuelist     # joins the recordings into Vendor/Build/<Pack>_Sounds.wav
    python3 Tools/hero_sounds.py upload ShadowDuelist    # uploads it and writes the Luau module
    python3 Tools/hero_sounds.py write ShadowDuelist     # only new cues: writes the module for the uploaded file

The upload uses the Open Cloud API key in the macOS Keychain (service DefendTheMaster.RobloxOpenCloud), with the
Assets read and write permissions; the key is never printed or written anywhere.
"""

import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
CREATOR_USER_ID = "11859499496"
KEYCHAIN_SERVICE = "DefendTheMaster.RobloxOpenCloud"
RATE = 44100
GAP = 0.3

PACKS = {
    "ShadowDuelist": {
        "folder": ROOT / "Vendor/ShadowDuelist/Sounds",
        "clips": [
            # Shadowren's attacks (Config.Heroes.Shadowren.Kit) and the clips under them.
            "RA-SHD-024", "RA-SHD-023", "RA-SHD-044", "RA-SHD-058", "RA-SHD-035", "RA-SHD-071", "RA-SHD-059",
            "RA-SHD-005", "RA-SHD-006", "RA-SHD-007", "RA-SHD-002", "RA-SHD-011", "RA-SHD-013",
        ],
        # The arena's floor is sand.
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "m", "gait_variant": "f"},
        # Recordings made here: the layers of other clips' recordings from a moment on (seconds), played together.
        # Their ground slams (clip 053 at 1.77 s, 086 at 1.50 s) come down where these begin.
        "mixes": {
            "Slam1": [("Afdc47bcc4bb6", 1.44), ("A59d6e22a68fe", 1.44)],
            "Slam2": [("A653ea09241ff", 1.17), ("A7a7571ebfb51", 1.17)],
        },
        # Sounds for the game's own events: the dagger let go (the pack leaves it to the game), and the ground
        # struck where the leap lands and where the ultimate comes down.
        "events": {
            "Release": (["Aa7631d4093ec"], 0.8),
            "Slam": (["Slam1", "Slam2"], 0.9),
        },
    },
    "Ranger": {
        "folder": ROOT / "Vendor/Ranger/Sounds",
        "clips": [
            # Rowan's attacks (Config.Heroes.Rowan.Kit) and the clips under them.
            "RA-RNG-036", "RA-RNG-040", "RA-RNG-041", "RA-RNG-048", "RA-RNG-058",
            "RA-RNG-005", "RA-RNG-006", "RA-RNG-007", "RA-RNG-002", "RA-RNG-011", "RA-RNG-013", "RA-RNG-030",
        ],
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "m", "gait_variant": "f"},
        # Cues added to clips the pack left without them (seconds, recordings, volume): his plain shot (036) has
        # only footsteps, so the release of his heavy shot (040's Sound 04, loudest 0.1 s in) sounds as its arrow goes.
        "extra": {
            "RA-RNG-036": [(0.30, ["Acfa330cd7291"], 0.6)],
        },
        "events": {},
    },
    "Elementalist": {
        "folder": ROOT / "Vendor/Elementalist/Sounds",
        "clips": [
            # Mavorak's attacks (Config.Heroes.Mavorak.Kit) and the clips under them.
            "RA-ELM-020", "RA-ELM-034", "RA-ELM-041", "RA-ELM-053", "RA-ELM-062", "RA-ELM-050", "RA-ELM-060",
            "RA-ELM-005", "RA-ELM-006", "RA-ELM-007", "RA-ELM-002", "RA-ELM-011", "RA-ELM-013",
        ],
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "m", "gait_variant": "f"},
        # Every orb of his combo sounds as the third's cast (041's Sound 02, owner 2026-10-30): the three keep only
        # their footsteps and get it as their orb goes (Config's Hit).
        "mute": ["RA-ELM-020", "RA-ELM-034", "RA-ELM-041"],
        "extra": {
            "RA-ELM-020": [(0.30, ["A372384195c2d"], 0.45)],
            "RA-ELM-034": [(0.37, ["A372384195c2d"], 0.45)],
            "RA-ELM-041": [(0.45, ["A372384195c2d"], 0.45)],
        },
        # The ultimate's great orb bursting: the other slam of his staff (053's second set), from where it strikes.
        # His staff's own slam (053's cue) already sounds as it comes down, so the pack's clips need no Slam.
        "mixes": {
            "Blast": [("A84e421561310", 0.25)],
        },
        "events": {
            "Blast": (["Blast"], 0.9),
        },
    },
    "GreataxeBerserker": {
        "folder": ROOT / "Vendor/GreataxeBerserker/Sounds",
        # The Masters' clips (Config.Master), by their names in ReplicatedStorage.GreataxeBerserker. The stance has no
        # cues.
        "clips": {
            "Guard": "RA-GBK-018",
            "Unguard": "RA-GBK-019",
            "Attack1": "RA-GBK-023",
            "Attack2": "RA-GBK-024",
            "Attack3": "RA-GBK-025",
            "Hit": "RA-GBK-026",
            "Death": "RA-GBK-033",
            "Frenzy": "RA-GBK-049",
            "Slam": "RA-GBK-044",
        },
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "m", "gait_variant": "f"},
        # The pack leaves the cloth to the game: his toga is the first garment, its body impacts the first profile.
        "pick": {
            "Clothing": lambda member, sound: any(
                c.get("family") == "body_movement" and c.get("garment") == 1 for c in member["choices"]
            ),
            "RA-GBK-026-S6782d7146e-Alternatives": lambda member, sound: "clothing profile 1 " in sound["file"],
        },
        "events": {},
    },
}


def load(pack):
    with open(pack["folder"] / "Roblox Integration/Sound Map.json") as f:
        return json.load(f)


def select(pack, sound_map):
    """The cues per clip, the footstep pool by contact, the events, and every recording they need."""
    needed = []

    def need(sound_id):
        if sound_id not in needed:
            needed.append(sound_id)
        return sound_id

    footsteps = {}
    want = pack["footsteps"]
    for member in sound_map["groups"]["Footsteps"]:
        for choice in member["choices"]:
            if choice.get("family") == "footstep" and all(choice.get(k) == v for k, v in want.items()):
                if choice["sound_index"] <= 1:
                    footsteps.setdefault(choice["sound_index"], []).append(need(member["soundId"]))
    contacts = [footsteps[i] for i in sorted(footsteps)]

    clips = {}
    named = pack["clips"] if isinstance(pack["clips"], dict) else {clip_id: clip_id for clip_id in pack["clips"]}
    for key, clip_id in named.items():
        animation = sound_map["animations"][clip_id]
        sets = sound_map["soundSets"].get(clip_id)
        routes = sets["sets"][sets["default"]]["routes"] if sets else None
        cues = []
        for cue_id in animation["cues"]:
            for played in routes.get(cue_id, []) if routes is not None else [cue_id]:
                cue = sound_map["cues"][played]
                entry = {"time": round(cue["time"], 4), "volume": round(cue["volume"], 3)}
                if cue["kind"] == "Footstep":
                    entry["footstep"] = True
                elif cue.get("soundIds"):
                    entry["sounds"] = [need(s) for s in cue["soundIds"]]
                elif cue.get("group"):
                    pick = pack.get("pick", {}).get(cue["group"], lambda member, sound: True)
                    members = sound_map["groups"][cue["group"]]
                    entry["sounds"] = [
                        need(m["soundId"]) for m in members if pick(m, sound_map["sounds"][m["soundId"]])
                    ]
                else:
                    continue
                # A muted clip's own recordings stay in the file, so the uploaded one still matches its regions.
                if clip_id in pack.get("mute", []) and not entry.get("footstep"):
                    continue
                cues.append(entry)
        for time, sounds, volume in pack.get("extra", {}).get(clip_id, []):
            cues.append({"time": time, "volume": volume, "sounds": list(sounds)})
        cues.sort(key=lambda c: c["time"])
        clips[key] = cues
    # The added cues' recordings go in after all the pack's own, so adding them never moves those in the file.
    for cues in clips.values():
        for cue in cues:
            for s in cue.get("sounds", []):
                need(s)

    events = {name: {"sounds": [need(s) for s in sounds], "volume": volume} for name, (sounds, volume) in pack["events"].items()}
    return clips, contacts, events, needed


def decode(path):
    """The recording as 16-bit mono samples at RATE."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(RATE), "-f", "s16le", "-"],
        check=True,
        capture_output=True,
    ).stdout
    return raw


def recording(pack, sound_map, sound_id):
    # The file names on disk do not always match the map's (dashes), the recording's id at their end does.
    folder = (pack["folder"] / sound_map["sounds"][sound_id]["file"]).parent
    return decode(next(folder.glob(f"* - {sound_id}.wav")))


def mix(layers):
    """The layers (samples, from this many seconds on) laid over each other, with a short fade in against clicks."""
    parts = [np.frombuffer(samples, np.int16)[int(start * RATE) :].astype(np.float64) for samples, start in layers]
    out = np.zeros(max(len(p) for p in parts))
    for p in parts:
        out[: len(p)] += p
    fade = int(0.005 * RATE)
    out[:fade] *= np.linspace(0, 1, fade)
    peak = np.abs(out).max()
    if peak > 32000:
        out *= 32000 / peak
    return out.astype(np.int16).tobytes()


def build(name):
    pack = PACKS[name]
    sound_map = load(pack)
    clips, contacts, events, needed = select(pack, sound_map)
    out = ROOT / "Vendor/Build"
    out.mkdir(parents=True, exist_ok=True)
    regions = {}
    data = bytearray()
    silence = bytes(int(GAP * RATE) * 2)
    for sound_id in needed:
        if sound_id in pack.get("mixes", {}):
            samples = mix([(recording(pack, sound_map, layer), start) for layer, start in pack["mixes"][sound_id]])
        else:
            samples = recording(pack, sound_map, sound_id)
        start = len(data) / 2 / RATE
        regions[sound_id] = [round(start, 4), round(len(samples) / 2 / RATE, 4)]
        data += samples + silence
    with wave.open(str(out / f"{name}_Sounds.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(data))
    layout = {"regions": regions, "clips": clips, "footsteps": contacts, "events": events}
    (out / f"{name}_Sounds.json").write_text(json.dumps(layout, indent=1))
    seconds = len(data) / 2 / RATE
    print(f"{name}: {len(needed)} recordings, {seconds:.1f} s, {len(data) / 1e6:.1f} MB -> Vendor/Build/{name}_Sounds.wav")


def api_key():
    result = subprocess.run(
        ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"], capture_output=True, text=True
    )
    if result.returncode != 0 or not result.stdout.strip():
        sys.exit(f"No Open Cloud API key in the Keychain (service {KEYCHAIN_SERVICE}).")
    return result.stdout.strip()


def request(url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method="POST" if body is not None else "GET")
    req.add_header("x-api-key", key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        sys.exit(f"{url}: HTTP {error.code} {error.read().decode(errors='replace')[:500]}")


def upload(name):
    out = ROOT / "Vendor/Build"
    path = out / f"{name}_Sounds.wav"
    layout = json.loads((out / f"{name}_Sounds.json").read_text())
    key = api_key()
    meta = {
        "assetType": "Audio",
        "displayName": f"DTM {name} sounds",
        "description": "Defend The Master: sound effects.",
        "creationContext": {"creator": {"userId": CREATOR_USER_ID}},
    }
    boundary = uuid.uuid4().hex
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n\r\n{json.dumps(meta)}\r\n"
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{path.name}\"\r\n"
        f"Content-Type: audio/wav\r\n\r\n"
    ).encode() + path.read_bytes() + f"\r\n--{boundary}--\r\n".encode()
    operation = request(
        "https://apis.roblox.com/assets/v1/assets", key, body, f"multipart/form-data; boundary={boundary}"
    )
    path_id = operation["path"]
    for _ in range(60):
        status = request(f"https://apis.roblox.com/assets/v1/{path_id}", key)
        if status.get("done"):
            break
        time.sleep(2)
    else:
        sys.exit(f"The upload did not finish: {path_id}")
    if "response" not in status:
        sys.exit(f"The upload failed: {json.dumps(status)[:500]}")
    asset_id = status["response"]["assetId"]
    moderation = status["response"].get("moderationResult", {}).get("moderationState", "?")
    print(f"Uploaded {path.name}: asset {asset_id} ({moderation})")
    write_module(name, f"rbxassetid://{asset_id}", layout)


def write(name):
    """Rewrites the module for new cues without a new upload, when the built file is the uploaded one."""
    module = ROOT / f"src/shared/PackSounds/{name}.luau"
    asset = next(line.split('"')[3] for line in module.read_text().splitlines() if '["Asset"]' in line)
    if not asset.startswith("rbxassetid://"):
        sys.exit(f"No uploaded asset in {module.relative_to(ROOT)}: upload the file instead.")
    uploaded = {k: float(v) for k, v in re.findall(r'\["(\w+)"\] = \{ ([\d.]+), [\d.]+ \}', module.read_text())}
    build(name)
    layout = json.loads((ROOT / f"Vendor/Build/{name}_Sounds.json").read_text())
    if {k: v[0] for k, v in layout["regions"].items()} != uploaded:
        sys.exit("The recordings changed: upload the file again instead.")
    write_module(name, asset, layout)


def lua(value, indent=1):
    pad = "\t" * indent
    if isinstance(value, dict):
        items = [f"{pad}[{json.dumps(k)}] = {lua(v, indent + 1)}," for k, v in value.items()]
        return "{\n" + "\n".join(items) + "\n" + "\t" * (indent - 1) + "}"
    if isinstance(value, list):
        return "{ " + ", ".join(lua(v, indent + 1) for v in value) + " }"
    if isinstance(value, bool):
        return "true" if value else "false"
    return json.dumps(value)


def write_module(name, asset, layout):
    cues = {
        clip: [
            {"Time": c["time"], "Volume": c["volume"], **({"Footstep": True} if c.get("footstep") else {"Sounds": c["sounds"]})}
            for c in entries
        ]
        for clip, entries in layout["clips"].items()
        if entries
    }
    events = {k: {"Sounds": v["sounds"], "Volume": v["volume"]} for k, v in layout["events"].items()}
    data = {
        "Asset": asset,
        "Regions": layout["regions"],
        "Cues": cues,
        "Footsteps": layout["footsteps"],
        "Events": events,
    }
    module = ROOT / f"src/shared/PackSounds/{name}.luau"
    module.parent.mkdir(parents=True, exist_ok=True)
    module.write_text(
        f"-- Generated by Tools/hero_sounds.py from the {name} pack's sound add-on; do not edit by hand.\n"
        "-- Asset: every recording in one uploaded file. Regions: where each sits in it (start, length in seconds).\n"
        "-- Cues: per clip, when (seconds into the clip) to play one of Sounds, or a footstep on the arena's floor.\n"
        "-- Footsteps: the recordings per foot contact, alternating. Events: sounds the game plays on its own events.\n"
        f"return {lua(data)}\n"
    )
    print(f"Wrote {module.relative_to(ROOT)}")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("build", "upload", "write") or sys.argv[2] not in PACKS:
        sys.exit(__doc__)
    {"build": build, "upload": upload, "write": write}[sys.argv[1]](sys.argv[2])
