#!/usr/bin/env python3
"""Unpacks the bought whole-pack ZIPs (KitsBlox, Docs/Third_Party.md) into Vendor/: the Shadow Duelist (Shadowren)
into Vendor/ShadowDuelist/, the Ranger (Rowan) into Vendor/Ranger/, the Elementalist (the dark mage) into
Vendor/Elementalist/, the Scythe Wielder (the reaper) into Vendor/ScytheWielder/, the Greatsword Knight into
Vendor/GreatswordKnight/, the Trickster Caster (the jester) into Vendor/TricksterCaster/, the Wildguard (Korrund)
into Vendor/Wildguard/, the Katana Swordsman (the samurai) into Vendor/KatanaSwordsman/, the Gunslinger into
Vendor/Gunslinger/ and the Arena Fighter (Haldrek) into Vendor/ArenaFighter/, each with its animations and its
sounds; and the Dance Collection (the emotes, Config.Emotes) into Vendor/DanceCollection/, animations only.

Their licence forbids sharing the files, so Vendor/ stays out of git: run this once on a new machine with the ZIPs
in ~/Downloads. Rojo serves each pack's playback module and rig from there (default.project.json).

    python3 Tools/vendor_shadow_duelist.py [ShadowDuelist] [Ranger] [Elementalist] [ScytheWielder] [GreatswordKnight]
        [TricksterCaster] [Wildguard] [KatanaSwordsman] [Gunslinger] [ArenaFighter] [DanceCollection]
"""

import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOWNLOADS = pathlib.Path.home() / "Downloads"
# Each ZIP, and the pack's folder in Vendor/ and the part of it this ZIP fills.
PACKS = {
    "RobloxAnimations-Shadow-Duelist-v1.2.0.zip": ("ShadowDuelist", "Animations"),
    "RobloxAnimations-Shadow-Duelist-Sounds-v1.3.1.zip": ("ShadowDuelist", "Sounds"),
    "RobloxAnimations-Ranger-v1.2.0.zip": ("Ranger", "Animations"),
    "RobloxAnimations-Ranger-Sounds-v1.3.1.zip": ("Ranger", "Sounds"),
    "RobloxAnimations-Elementalist-v1.1.1.zip": ("Elementalist", "Animations"),
    "RobloxAnimations-Elementalist-Sounds-v1.3.1.zip": ("Elementalist", "Sounds"),
    "RobloxAnimations-Scythe-Wielder-v1.3.0.zip": ("ScytheWielder", "Animations"),
    "RobloxAnimations-Scythe-Wielder-Sounds-v1.3.1.zip": ("ScytheWielder", "Sounds"),
    "RobloxAnimations-Greatsword-Knight-v1.2.1.zip": ("GreatswordKnight", "Animations"),
    "RobloxAnimations-Greatsword-Knight-Sounds-v1.2.1.zip": ("GreatswordKnight", "Sounds"),
    "RobloxAnimations-Trickster-Caster-v1.1.0.zip": ("TricksterCaster", "Animations"),
    "RobloxAnimations-Trickster-Caster-Sounds-v1.3.1.zip": ("TricksterCaster", "Sounds"),
    "RobloxAnimations-Wildguard-v1.1.0.zip": ("Wildguard", "Animations"),
    "RobloxAnimations-Wildguard-Sounds-v1.3.1.zip": ("Wildguard", "Sounds"),
    "RobloxAnimations-Katana-Swordsman-v1.2.0.zip": ("KatanaSwordsman", "Animations"),
    "RobloxAnimations-Katana-Swordsman-Sounds-v1.3.1.zip": ("KatanaSwordsman", "Sounds"),
    "RobloxAnimations-Gunslinger-v1.2.0.zip": ("Gunslinger", "Animations"),
    "RobloxAnimations-Gunslinger-Sounds-v1.3.1.zip": ("Gunslinger", "Sounds"),
    "RobloxAnimations-Arena-Fighter-v1.1.0.zip": ("ArenaFighter", "Animations"),
    "RobloxAnimations-Arena-Fighter-Sounds-v1.3.1.zip": ("ArenaFighter", "Sounds"),
    "RobloxAnimations-Dance-Collection-v1.1.0.zip": ("DanceCollection", "Animations"),
}


def clean(part: str) -> str:
    # Some names in the ZIPs carry broken dashes; keep them plain ASCII.
    return re.sub(r"[^\w .,()+-]+", "-", part).strip()


def main() -> int:
    only = set(sys.argv[1:])
    for name, (pack_name, folder) in PACKS.items():
        if only and pack_name not in only:
            continue
        source = DOWNLOADS / name
        if not source.exists():
            print(f"missing {source}")
            return 1
        with zipfile.ZipFile(source) as pack:
            count = 0
            for info in pack.infolist():
                if info.is_dir():
                    continue
                parts = info.filename.split("/")[1:] or [info.filename]
                target = ROOT / "Vendor" / pack_name / folder / pathlib.Path(*[clean(p) for p in parts])
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(pack.read(info))
                count += 1
            print(f"{pack_name}/{folder}: {count} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
