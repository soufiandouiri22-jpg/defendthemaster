#!/usr/bin/env python3
"""Unpacks the bought KitsBlox motions (one ZIP per motion, Docs/Third_Party.md) into Vendor/, for the Masters: the
Greataxe Berserker's fight into Vendor/GreataxeBerserker/ and the Armorer's walking into Vendor/Armorer/; and the
Greataxe Berserker's sound add-on into Vendor/GreataxeBerserker/Sounds/ (Tools/hero_sounds.py).

Their licence forbids sharing the files, so Vendor/ stays out of git: run this once on a new machine with the ZIPs
(ANM-KBX-RA-GBK-*.zip, ANM-KBX-RA-ARM-*.zip, RobloxAnimations-Greataxe-Berserker-Sounds-*.zip) in ~/Downloads. Each
motion goes into a folder named after its asset id, its bonus variations into their own.

    python3 Tools/vendor_kitsblox.py
"""

import json
import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOWNLOADS = pathlib.Path.home() / "Downloads"
# Each pack's code in the ZIP names, and its folder in Vendor/.
PACKS = {"GBK": "GreataxeBerserker", "ARM": "Armorer"}
# The packs' sound add-ons, and their folder in Vendor/.
SOUNDS = {"RobloxAnimations-Greataxe-Berserker-Sounds-*.zip": "GreataxeBerserker/Sounds"}


def clean(part: str) -> str:
    # Some names in the ZIPs carry broken dashes; keep them plain ASCII.
    return re.sub(r"[^\w .,()+-]+", "-", part).strip()


def unpack_sounds() -> int:
    found = 0
    for pattern, folder in SOUNDS.items():
        for source in sorted(DOWNLOADS.glob(pattern)):
            found += 1
            with zipfile.ZipFile(source) as pack:
                count = 0
                for info in pack.infolist():
                    if info.is_dir():
                        continue
                    parts = info.filename.split("/")[1:] or [info.filename]
                    target = ROOT / "Vendor" / folder / pathlib.Path(*[clean(p) for p in parts])
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(pack.read(info))
                    count += 1
            print(f"{folder}: {count} files")
    return found


def main() -> int:
    found = 0
    for code, name in PACKS.items():
        for source in sorted(DOWNLOADS.glob(f"ANM-KBX-RA-{code}-*.zip")):
            found += 1
            with zipfile.ZipFile(source) as pack:
                certificate = json.loads(pack.read("Kitsblox-License-Certificate.json"))
                folder = ROOT / "Vendor" / name / certificate["asset_id"]
                for info in pack.infolist():
                    if info.is_dir():
                        continue
                    target = folder / info.filename
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(pack.read(info))
                print(f"{certificate['asset_id']}: {certificate['product']}")
    found += unpack_sounds()
    if not found:
        print(f"no KitsBlox ZIPs in {DOWNLOADS}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
