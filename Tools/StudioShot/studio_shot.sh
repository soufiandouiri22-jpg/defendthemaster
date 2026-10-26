#!/bin/zsh
# Saves the Studio viewport (the game view in Play) as a PNG, even when Studio is behind other windows.
# Usage: Tools/StudioShot/studio_shot.sh <out.png>
set -e
here=${0:A:h}
bin=/tmp/dtm/studio_window
if [[ ! -x $bin || $here/studio_window.swift -nt $bin ]]; then
	mkdir -p /tmp/dtm
	swiftc -O $here/studio_window.swift -o $bin
fi
id=$($bin)
[[ -n $id ]] || { echo "Roblox Studio window not found" >&2; exit 1; }
raw=/tmp/dtm/studio_window.png
screencapture -x -o -l $id $raw
# The viewport, as a share of the window: below the ribbon and tabs, left of the Explorer, above the command bar.
python3 - $raw $1 <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
im.crop((int(w * 0.002), int(h * 0.178), int(w * 0.846), int(h * 0.915))).save(sys.argv[2])
print(sys.argv[2])
EOF
