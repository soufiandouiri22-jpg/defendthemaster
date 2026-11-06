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
    "ScytheWielder": {
        "folder": ROOT / "Vendor/ScytheWielder/Sounds",
        "clips": [
            # Mortael's attacks (Config.Heroes.Mortael.Kit) and the clips under them.
            "RA-SCW-023", "RA-SCW-024", "RA-SCW-025", "RA-SCW-038", "RA-SCW-035", "RA-SCW-086", "RA-SCW-057",
            "RA-SCW-005", "RA-SCW-006", "RA-SCW-007", "RA-SCW-002", "RA-SCW-011", "RA-SCW-013", "RA-SCW-033",
        ],
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "m", "gait_variant": "f"},
        # His fall's cloth: the first garment's body movements only, not all 49 of the pack's.
        "pick": {
            "Clothing": lambda member, sound: any(
                c.get("family") == "body_movement" and c.get("garment") == 1 for c in member["choices"]
            ),
        },
        # The dash plays 057 at 1.2 times for a moment only, too short for its two long recordings (3.6 and 4.1 s):
        # it keeps a quick swish of the first basic attack as he sets off (Start 0.5 s, 0.6 s into the clip).
        "mute": ["RA-SCW-057"],
        "extra": {
            "RA-SCW-057": [(0.55, ["A1673babe6052", "A715b73045d72", "Aec6ee6730a76"], 0.8)],
            # The finisher has no cues: the basic attack's swishes (loudest about 0.06 s in) on each swing of its
            # blade (fastest at 0.35, 0.60, 0.75, 2.00 and pulled from the ground at 2.30 s), a step and his cloth as
            # he jumps (1.40 s); the ground struck where he lands is the Slam event.
            "RA-SCW-086": [
                (0.29, ["A1673babe6052", "A715b73045d72", "Aec6ee6730a76"], 0.7),
                (0.54, ["A1673babe6052", "A715b73045d72", "Aec6ee6730a76"], 0.7),
                (0.69, ["A1673babe6052", "A715b73045d72", "Aec6ee6730a76"], 0.6),
                (1.36, ["A71849bc6957b", "A52c8b099fb37", "A04a16cb4c370"], 0.5),
                (1.38, ["A1fe7fbf5cd09", "Af3065edadcc9", "Af2d53416ac23"], 0.7),
                (1.94, ["A1673babe6052", "A715b73045d72", "Aec6ee6730a76"], 0.9),
                (2.24, ["A1673babe6052", "A715b73045d72", "Aec6ee6730a76"], 0.45),
            ],
        },
        # Recordings no cue plays any more that stay in the uploaded file, so its regions keep matching: 058's
        # three swishes, the finisher's sound before 2026-10-31, which ran out of step with it.
        "keep": ["A4eac67974f6b"],
        # The ground struck where his leaps land: 072's scythe dropping (loudest 0.22 s in) over 038's hard knock.
        "mixes": {
            "Slam": [("Ab5c6cdc947da", 0.12), ("A452150559a77", 0.0)],
        },
        "events": {
            "Slam": (["Slam"], 0.9),
        },
    },
    "GreatswordKnight": {
        "folder": ROOT / "Vendor/GreatswordKnight/Sounds",
        "clips": [
            # Brontar's attacks (Config.Heroes.Brontar.Kit) and the clips under them.
            "RA-GSK-023", "RA-GSK-024", "RA-GSK-060", "RA-GSK-043", "RA-GSK-049", "RA-GSK-068", "RA-GSK-056",
            "RA-GSK-005", "RA-GSK-006", "RA-GSK-007", "RA-GSK-002", "RA-GSK-011", "RA-GSK-013", "RA-GSK-033",
        ],
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "m", "gait_variant": "f"},
        "pick": {
            "Clothing": lambda member, sound: any(
                c.get("family") == "body_movement" and c.get("garment") == 1 for c in member["choices"]
            ),
        },
        # The combo's finisher swings as the first two (owner, 2026-10-31: its own spin and heavy blow were too heavy to
        # hear on every basic attack): their swing, loudest 0.04 s in, on its blow at 0.98 s of the clip played 2.2
        # times as fast.
        "mute": ["RA-GSK-060"],
        "extra": {
            "RA-GSK-060": [(0.89, ["A3c9d46617057", "Affbd494f9af1", "A9e079ff9b56d"], 0.4)],
        },
        "events": {},
    },
    "TricksterCaster": {
        "folder": ROOT / "Vendor/TricksterCaster/Sounds",
        "clips": [
            # Jestrel's attacks (Config.Heroes.Jestrel.Kit) and the clips under them.
            "RA-TRC-023", "RA-TRC-034", "RA-TRC-053", "RA-TRC-041", "RA-TRC-046", "RA-TRC-045", "RA-TRC-042",
            "RA-TRC-040", "RA-TRC-005", "RA-TRC-006", "RA-TRC-007", "RA-TRC-002", "RA-TRC-011", "RA-TRC-013",
            "RA-TRC-031",
        ],
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "m", "gait_variant": "f"},
        "pick": {
            "Clothing": lambda member, sound: any(
                c.get("family") == "body_movement" and c.get("garment") == 1 for c in member["choices"]
            ),
        },
        # The combo's flick (034) lays 17 long spells over each other, too much on every basic attack: it swings as
        # the first hit (023's swish, loudest 0.12 s in) as its laser goes at 0.32 s.
        # The combo's last hit (053) sounds as the first two (owner, 2026-11-01): the same swish as its laser goes
        # at 0.48 s.
        # His rain (042) drops its 9 s swell, which sounded like a storm (owner, 2026-11-01): it keeps its leap's
        # spell, and every laser of the rain zaps as his other beams do (HeroControls).
        "mute": ["RA-TRC-034", "RA-TRC-053", "RA-TRC-042"],
        "extra": {
            "RA-TRC-034": [(0.20, ["A6c428b2ea4fa", "Ac37241325b76", "Ac8b73b92c836"], 0.5)],
            "RA-TRC-053": [(0.40, ["A6c428b2ea4fa", "Ac37241325b76", "Ac8b73b92c836"], 0.5)],
            # The leap's second spell (045's at 0.667 s) as well, which 042 cut off taking over at ThenAt (0.27 s).
            "RA-TRC-042": [(0.0, ["A84c4477603c4"], 0.25), (0.40, ["Af919c19de755"], 0.76)],
            # His vanishing trick (040, only footsteps in the pack; owner, 2026-11-01): the casting gestures' spell,
            # loudest 0.25 s in as he is gone (Config's Cast).
            "RA-TRC-040": [(0.0, ["Aa8fb53ce845a"], 0.6)],
        },
        "keep": ["A65e2cc9594ed", "Ad72586826982", "A2ec6057db100"],
        # Every laser beam he shoots (his combo's, his E's): a short bright spell of 033 (Sound 19, loudest 0.13 s in).
        "events": {
            "Release": (["A86d1985907b6"], 0.6),
        },
    },
    "Wildguard": {
        "folder": ROOT / "Vendor/Wildguard/Sounds",
        "clips": [
            # Korrund's attacks (Config.Heroes.Korrund.Kit) and the clips under them.
            "RA-WGD-025", "RA-WGD-026", "RA-WGD-027", "RA-WGD-057", "RA-WGD-058", "RA-WGD-056", "RA-WGD-008",
            "RA-WGD-005", "RA-WGD-006", "RA-WGD-007", "RA-WGD-002", "RA-WGD-011", "RA-WGD-013", "RA-WGD-035",
        ],
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "m", "gait_variant": "f"},
        "pick": {
            "Clothing": lambda member, sound: any(
                c.get("family") == "body_movement" and c.get("garment") == 1 for c in member["choices"]
            ),
        },
        # His dash is the pack's sprint (008), which has only footsteps (owner, 2026-11-03: silent): Brontar's dash
        # (the Greatsword Knight's Phantom Advance, 056's Sound 01, loudest 0.28 s in) as he sets off (Start 0.05 s),
        # played from that pack's file.
        "extra": {
            "RA-WGD-008": [(0.0, ["Aa053ab1b21fe"], 0.76, "GreatswordKnight")],
        },
        "events": {},
    },
    "KatanaSwordsman": {
        "folder": ROOT / "Vendor/KatanaSwordsman/Sounds",
        "clips": [
            # Kaeda's attacks (Config.Heroes.Kaeda.Kit) and the clips under them.
            "RA-KAT-023", "RA-KAT-024", "RA-KAT-025", "RA-KAT-059", "RA-KAT-069", "RA-KAT-066", "RA-KAT-074",
            "RA-KAT-005", "RA-KAT-006", "RA-KAT-007", "RA-KAT-002", "RA-KAT-011", "RA-KAT-013", "RA-KAT-033",
        ],
        # Her steps are a woman's.
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "f", "gait_variant": "f"},
        "pick": {
            "Clothing": lambda member, sound: any(
                c.get("family") == "body_movement" and c.get("garment") == 1 for c in member["choices"]
            ),
        },
        # Her leap's landing (069) and her ultimate's slam (066) already sound in their clips' own recordings, so
        # they need no Slam.
        "events": {},
    },
    "Gunslinger": {
        "folder": ROOT / "Vendor/Gunslinger/Sounds",
        "clips": [
            # Corvin's attacks (Config.Heroes.Corvin.Kit) and the clips under them.
            "RA-GSL-087", "RA-GSL-086", "RA-GSL-033", "RA-GSL-045", "RA-GSL-065", "RA-GSL-043",
            "RA-GSL-005", "RA-GSL-006", "RA-GSL-007", "RA-GSL-002", "RA-GSL-011", "RA-GSL-013", "RA-GSL-030",
        ],
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "m", "gait_variant": "f"},
        "pick": {
            "Clothing": lambda member, sound: any(
                c.get("family") == "body_movement" and c.get("garment") == 1 for c in member["choices"]
            ),
            # The bomb round's recording: of its two takes only the first fires where the revolver kicks (0.99 s), as
            # the kit's Release does.
            "RA-GSL-045-S1cc3e3b326-Alternatives": lambda member, sound: member["soundId"] == "A1db15aab73d5",
        },
        # His sniper shot (065) stops at its aim (AimAt 1.0 s) until he fires, and plays on from its kick (Kick
        # 1.4 s): its two recordings, which run through the shot at 1.35 s, are cut where he holds. The rifle raised
        # (Sound 02, 0.17 s) and its click (Sound 01, 0.5 s) sound as he aims, the shot (both from just before their
        # crack at 1.35 s) as he fires.
        # His quick shots (087, 086) keep their own three recordings (owner, 2026-11-04): the short crack tried
        # instead, the first shot of 086's Sound 01 without its rumble (`highpass`, Hz), sounded too light. It stays
        # in the uploaded file where 087's cue had it (`keep_in`), unplayed. Both shots sound as the first (owner,
        # 2026-11-04): 086 plays the same recordings, its main one 0.4 s later, and its revolver kicks when 087's does.
        # Their first two recordings are the revolver drawn, at the clip's start: a shot held on starts after them
        # (Config's `Follow`, 0.27 s), so only the first sounds them (owner, 2026-11-04). Their laser (Sound 02) has
        # two parts, a soft one from its start and its loud blast from 0.77 s: played whole with every shot, the
        # blast came as the next shot left and once more after the last. Its parts play from the uploaded file
        # (`parts`, from and to seconds in its recording, cut where it is quietest): the soft one with the draw, the
        # blast with every shot as the bullet leaves (Hit 0.38). Pixabay's pistol shot (Docs/Third_Party.md), from
        # just before its crack (0.15 s in the download) to where it has died away, was tried in its place the same
        # day; it stays in the uploaded file where 087's added cue had it (`keep_in`), unplayed.
        "same_cues": {"RA-GSL-086": "RA-GSL-087"},
        "files": {"PistolShot": (ROOT / "Vendor/Pixabay/universfield-pistol-shot-278821.mp3", 0.14, 1.0)},
        "mute": ["RA-GSL-065", "RA-GSL-087"],
        "mixes": {
            "SnipeRaise": [("A91ac2edf0475", 0.0, 1.0)],
            "SnipeClick": [("A814aa8cfd43e", 0.0, 0.4)],
            "SnipeShot": [("A814aa8cfd43e", 0.83), ("A91ac2edf0475", 1.163)],
            "RevolverShot": [("A795daf539aa1", 0.06, 0.42)],
        },
        "highpass": {"RevolverShot": 180},
        "keep_in": {"RA-GSL-087": ["PistolShot", "RevolverShot"]},
        "parts": {"LaserHum": ("Ab1f5b2934b4f", 0.0, 0.755), "LaserBlast": ("Ab1f5b2934b4f", 0.755, 1.8018)},
        "extra": {
            "RA-GSL-065": [(0.167, ["SnipeRaise"], 0.8), (0.5, ["SnipeClick"], 0.76), (1.4, ["SnipeShot"], 0.8)],
            "RA-GSL-087": [
                (0.0, ["A795daf539aa1"], 0.855),
                (0.0, ["Ab5c6cdc947da"], 0.2),
                (0.0667, ["LaserHum"], 0.57),
                (0.38, ["LaserBlast"], 0.57),
            ],
        },
        # Every other shot already sounds in its clip's own recording.
        "events": {},
    },
    "ArenaFighter": {
        "folder": ROOT / "Vendor/ArenaFighter/Sounds",
        "clips": [
            # Haldrek's attacks (Config.Heroes.Haldrek.Kit) and the clips under them.
            "RA-ARF-027", "RA-ARF-028", "RA-ARF-029", "RA-ARF-074", "RA-ARF-073", "RA-ARF-042", "RA-ARF-008",
            "RA-ARF-005", "RA-ARF-006", "RA-ARF-007", "RA-ARF-002", "RA-ARF-011", "RA-ARF-013", "RA-ARF-038",
        ],
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "m", "gait_variant": "f"},
        "pick": {
            "Clothing": lambda member, sound: any(
                c.get("family") == "body_movement" and c.get("garment") == 1 for c in member["choices"]
            ),
        },
        # His flurry (042) has only footsteps in its clip: the pack plays its recordings as the move begins (its
        # additionalSounds, CustomEvent), the shared start as 073's and 074's do, and its two takes from there, whose
        # loudest blow (1.4 s) is the slam (Hit 1.38). His sprint (008) has only footsteps: the same start as a whoosh.
        # His E strikes in place since 2026-11-05 (owner: only the blow and its sound, no charge): 073's own recordings
        # are his cry and his run (Sound 02) and his spin into the blow (Sound 01: its whoosh, then the blow 0.48 s
        # into it, 0.95 s into the clip, the sword's strike at 0.92). Only Sound 01 plays, whole at its own time (the
        # owner: the spin is heard with it), without the clip's footsteps (`still`). ChargeBlow, the blow alone that
        # played before, stays in the uploaded file (`keep_in`).
        "mute": ["RA-ARF-073"],
        "still": ["RA-ARF-073"],
        "mixes": {"ChargeBlow": [("A923567fe6b05", 0.48)]},
        "keep_in": {"RA-ARF-073": ["ChargeBlow"]},
        "extra": {
            "RA-ARF-042": [(0.0, ["Ab5c6cdc947da"], 0.2), (0.0, ["A4177c480f3bc"], 0.95), (0.0, ["Aa8921b2db493"], 0.76)],
            "RA-ARF-008": [(0.0, ["Ab5c6cdc947da"], 0.35)],
            "RA-ARF-073": [(0.4667, ["A923567fe6b05"], 0.684)],
        },
        # Both slams (074 at 1.48 s, 042 at 1.38 s) already sound in their recordings, so they need no Slam.
        "events": {},
    },
    "Lancer": {
        "folder": ROOT / "Vendor/Lancer/Sounds",
        "clips": [
            # Renka's attacks (Config.Heroes.Renka.Kit) and the clips under them.
            "RA-LAN-023", "RA-LAN-024", "RA-LAN-025", "RA-LAN-046", "RA-LAN-049", "RA-LAN-061", "RA-LAN-052",
            "RA-LAN-005", "RA-LAN-006", "RA-LAN-007", "RA-LAN-002", "RA-LAN-011", "RA-LAN-013", "RA-LAN-033",
        ],
        # Her steps are a woman's.
        "footsteps": {"surface": "sand", "footwear": "boots", "character_variant": "f", "gait_variant": "f"},
        "pick": {
            "Clothing": lambda member, sound: any(
                c.get("family") == "body_movement" and c.get("garment") == 1 for c in member["choices"]
            ),
        },
        # Her vault (052) has a second recording the pack plays as the move begins (its additionalSounds,
        # CustomEvent): its whoosh as she sets off. Her spiral strike's (046) own recordings begin at 0.5 s, with
        # its second blow, so its first (Hit 0.25, owner 2026-11-06: not heard) gets her basic attacks' spear swing
        # (Sound 03, loudest 0.15 to 0.27 s in).
        "extra": {
            "RA-LAN-052": [(0.0, ["A9099b14772c0"], 0.8)],
            "RA-LAN-046": [(0.05, ["A7e8637a5f932"], 0.8)],
        },
        # Her ultimate's dive (061, down at 1.18 s) already sounds in its own recording, and her vault onto the spot
        # (049) lands without a blow, so they need no Slam.
        "events": {},
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
        if sound_id in pack.get("parts", {}):
            need(pack["parts"][sound_id][0])
        elif sound_id not in needed:
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
        # A clip the pack left without any sound (the Scythe Wielder's finisher) has only the cues added here.
        animation = sound_map["animations"].get(clip_id, {"cues": []})
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
                # A clip played in place (`still`) has no footsteps.
                if clip_id in pack.get("still", []) and entry.get("footstep"):
                    continue
                cues.append(entry)
        # An added cue may play another pack's recordings (its fourth value), from that pack's uploaded file.
        for time, sounds, volume, *bank in pack.get("extra", {}).get(clip_id, []):
            entry = {"time": time, "volume": volume, "sounds": list(sounds)}
            if bank:
                entry["bank"] = bank[0]
            cues.append(entry)
        cues.sort(key=lambda c: c["time"])
        clips[key] = cues
    # Clips that sound as another does, its cues at the same times.
    for key, like in pack.get("same_cues", {}).items():
        clips[key] = [dict(cue) for cue in clips[like]]
    # The added cues' recordings go in after all the pack's own, so adding them never moves those in the file; a
    # clip's `keep_in` stay where its added cues had them when they no longer play.
    for key, cues in clips.items():
        for cue in cues:
            for s in cue.get("sounds", []) if not cue.get("bank") else []:
                need(s)
        for s in pack.get("keep_in", {}).get(key, []):
            need(s)
    for s in pack.get("keep", []):
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
    """The layers (samples, from this many seconds on, up to that many when a third is given) laid over each other,
    with a short fade in against clicks, and a fade out where a layer is cut short."""
    parts = []
    for samples, start, *end in layers:
        part = np.frombuffer(samples, np.int16)[int(start * RATE) : int(end[0] * RATE) if end else None]
        part = part.astype(np.float64)
        if end:
            tail = min(int(0.04 * RATE), len(part))
            part[len(part) - tail :] *= np.linspace(1, 0, tail)
        parts.append(part)
    out = np.zeros(max(len(p) for p in parts))
    for p in parts:
        out[: len(p)] += p
    fade = int(0.005 * RATE)
    out[:fade] *= np.linspace(0, 1, fade)
    peak = np.abs(out).max()
    if peak > 32000:
        out *= 32000 / peak
    return out.astype(np.int16).tobytes()


def thin(samples, cutoff):
    """The samples with what lies below `cutoff` Hz taken away (two one-pole high-passes, 12 dB an octave)."""
    x = np.frombuffer(samples, np.int16).astype(np.float64)
    a = 1 / (1 + 2 * np.pi * cutoff / RATE)
    for _ in range(2):
        y = np.zeros_like(x)
        for i in range(1, len(x)):
            y[i] = a * (y[i - 1] + x[i] - x[i - 1])
        x = y
    return np.clip(x, -32000, 32000).astype(np.int16).tobytes()


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
        if sound_id in pack.get("files", {}):
            path, *cut = pack["files"][sound_id]
            samples = mix([(decode(path), *cut)])
        elif sound_id in pack.get("mixes", {}):
            samples = mix([(recording(pack, sound_map, layer), *cut) for layer, *cut in pack["mixes"][sound_id]])
            if sound_id in pack.get("highpass", {}):
                samples = thin(samples, pack["highpass"][sound_id])
        else:
            samples = recording(pack, sound_map, sound_id)
        start = len(data) / 2 / RATE
        regions[sound_id] = [round(start, 4), round(len(samples) / 2 / RATE, 4)]
        data += samples + silence
    for part, (sound_id, start, end) in pack.get("parts", {}).items():
        regions[part] = [round(regions[sound_id][0] + start, 4), round(end - start, 4)]
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
    parts = PACKS[name].get("parts", {})
    uploaded = {
        k: float(v)
        for k, v in re.findall(r'\["(\w+)"\] = \{ ([\d.]+), [\d.]+ \}', module.read_text())
        if k not in parts
    }
    build(name)
    layout = json.loads((ROOT / f"Vendor/Build/{name}_Sounds.json").read_text())
    if {k: v[0] for k, v in layout["regions"].items() if k not in parts} != uploaded:
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
            {
                "Time": c["time"],
                "Volume": c["volume"],
                **({"Footstep": True} if c.get("footstep") else {"Sounds": c["sounds"]}),
                **({"Bank": c["bank"]} if c.get("bank") else {}),
            }
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
        "-- Cues: per clip, when (seconds into the clip) to play one of Sounds (from the pack Bank's file when it has\n"
        "-- one), or a footstep on the arena's floor.\n"
        "-- Footsteps: the recordings per foot contact, alternating. Events: sounds the game plays on its own events.\n"
        f"return {lua(data)}\n"
    )
    print(f"Wrote {module.relative_to(ROOT)}")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("build", "upload", "write") or sys.argv[2] not in PACKS:
        sys.exit(__doc__)
    {"build": build, "upload": upload, "write": write}[sys.argv[1]](sys.argv[2])
