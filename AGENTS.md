# Defend The Master

A 4v4 Roblox arena game. Each team defends its Master, an NPC king on his throne; a team wins when the other
team's Master dies. The owner's designs in `Docs/Designs/Redesign_2026-10-26/dtm_design_01..09` are the measure for
everything: arena (01), throne room (02), spawn pads (03), hero (04), HUD (05), ability indicators (06), draft (07),
shop (08), cursors (09). Talk to the owner in Dutch.

## Game rules
- 4 heroes per team; empty slots are filled by bots.
- The Master is always an NPC king: 20,000 HP, never heals, sits on his throne, stands up to fight when enemies come
  close, then sits down again. He is clearly bigger than the heroes (scale about 1.8). White tunic, red sash and cape,
  crown, gold sword; the blue team's Master wears the same in blue.
- Every character (heroes, king, crowd) is a Roblox R15 avatar. The world and the statues come from Meshy, with
  variants so nothing repeats.
- Draft like League of Legends without bans: in turns with a timer, each hero once per match, the same category is
  fine, no trading. Teams are told apart only by the HP bar (red or blue).
- Attacks: left mouse a three-hit combo, right mouse and E specials, R the ultimate; built on the bought animation
  packs, damage lands on the hit frame. League-style indicators: hold to aim (arrow, circle, cone), release to cast.
- Abilities rank up with 1, 2 and 3. A shop at the own base (coins, 6 inventory slots). Own crosshair and cursor.
- The scoreboard follows League of Legends, mixed with the game's own design (owner, 2026-10-27): held on Tab, both
  teams with every hero's portrait, level, items and kills / deaths / assists; the player's own KDA stays in his HUD.

## Working rules
- Meshy models enter Studio only through File > Import 3D, as the unedited GLB from Meshy. Never EditableMesh or
  JSON imports (they have no MeshId and turn into boxes in Play), and never rebuild a model from Parts. The one
  change allowed is the blue team copies: `Tools/team_recolor.py` turns only the red pixels of the red piece's texture
  blue, so gold, stone and wood match exactly (a Meshy retexture repaints everything).
- After importing, check each piece: MeshId is a real `rbxassetid` (MeshContent source Uri), shape and texture are
  right, the front faces -Z. Set the pivot at the bottom centre and keep the pieces in `ServerStorage.ColosseumKit`.
  With a PrimaryPart, `Model.WorldPivot` is ignored: set `PrimaryPart.PivotOffset` instead. The imports come in at
  Meshy's metre size (about 1.9 studs); scale them with `Model:ScaleTo` when building.
- After every step: screenshots from Play (not Edit), from the design's angle, next to the design; the owner approves;
  only then a local commit.
- Every image for the owner (concepts, screenshots, designs) goes into the chat itself, embedded with its file path,
  not only named or saved (owner, 2026-10-26). Play captures are saved as a file first so they can be shown:
  `Tools/StudioShot/studio_shot.sh <out.png>` saves Studio's viewport, also when Studio is behind other windows.
- New Meshy models: first a concept (image-to-image) the owner approves, then 3D. Never generate without his go.
  Meshy is shared with RuneVille: never buy credits.
- Portraits (heroes and Masters, owner 2026-10-27) are made one way: Meshy image-to-image (nano-banana-pro) from a
  Play screenshot of the character with `Art/Portraits/shadowren.png` as the second reference for the painting style
  and the bust framing only. Every portrait stays its own: its pose, action, effects and background fit the hero and
  are never copied from another. Fixed are only the direction, chest and eyes towards the right of the picture or
  straight at the camera but never to the left, and the weapon in the hand he holds it in in the game; the prompt
  names both. A blue
  team copy is the red one recoloured locally (only the saturated reds, never the skin), so it matches exactly.
- Keys only in the macOS Keychain. Third-party assets need a recorded source and licence (`Docs/Third_Party.md`).

## Tools
- Rojo 7.7.1, StyLua and selene through Rokit (`~/.rokit/bin`): `rojo serve`, `stylua src`, `selene src`.
- `Art/Models/` holds the Meshy GLBs; `Art/Import/` is the staging folder for Import 3D (not in git).
- `Tools/kit_sheet.py` renders GLBs in Blender: `blender -b -P Tools/kit_sheet.py -- <folder> <out>`.
