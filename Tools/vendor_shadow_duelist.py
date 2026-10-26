#!/usr/bin/env python3
"""Unpacks the bought Shadow Duelist packs (KitsBlox, Docs/Third_Party.md) into Vendor/ShadowDuelist/.

Their licence forbids sharing the files, so Vendor/ stays out of git: run this once on a new machine with the two ZIPs
in ~/Downloads. Rojo serves the playback module and the rig from there (default.project.json).

    python3 Tools/vendor_shadow_duelist.py
"""

import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Vendor" / "ShadowDuelist"
DOWNLOADS = pathlib.Path.home() / "Downloads"
PACKS = {
    "RobloxAnimations-Shadow-Duelist-v1.2.0.zip": "Animations",
    "RobloxAnimations-Shadow-Duelist-Sounds-v1.3.1.zip": "Sounds",
}


def clean(part: str) -> str:
    # Some names in the ZIPs carry broken dashes; keep them plain ASCII.
    return re.sub(r"[^\w .,()+-]+", "-", part).strip()


def main() -> int:
    for name, folder in PACKS.items():
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
                target = OUT / folder / pathlib.Path(*[clean(p) for p in parts])
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(pack.read(info))
                count += 1
            print(f"{folder}: {count} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
