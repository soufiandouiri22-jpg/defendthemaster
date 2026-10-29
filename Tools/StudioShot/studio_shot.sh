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
# The viewport: inside the blue frame Studio draws round it, found along a line across and a line down the window's
# middle; without the frame, as a share of the window (below the ribbon and tabs, left of the Explorer, above the
# command bar).
python3 - $raw $1 <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size

def blue(p):
	r, g, b = p
	return b > 200 and r < 90 and 90 < g < 170

def edges(points):
	found = [i for i, p in enumerate(points) if blue(p)]
	if len(found) < 2:
		return None
	first, last = found[0], found[-1]
	while first + 1 in found:
		first += 1
	while last - 1 in found:
		last -= 1
	return (first + 1, last) if last - first > 100 else None

across = edges([im.getpixel((x, int(h * 0.5))) for x in range(w)])
down = edges([im.getpixel((int(w * 0.4), y)) for y in range(h)])
if across and down:
	box = (across[0], down[0], across[1], down[1])
else:
	box = (int(w * 0.002), int(h * 0.178), int(w * 0.846), int(h * 0.915))
im.crop(box).save(sys.argv[2])
print(sys.argv[2])
EOF
