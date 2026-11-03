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
- The heroes keep their layered clothing (owner, 2026-11-03). Roblox sometimes stops drawing a hero's layered
  clothing in a match, and the body under it goes with it (heroes with only hair and weapons left, 2026-11-03, a
  known engine bug after respawns). Workspace's `LayeredClothingCacheOptimizations` stays `Disabled` (set in Studio's
  Properties, Behavior; scripts and Rojo cannot reach it), Roblox's own workaround; `ClothingWatch` logs every change
  to a hero's clothing ("clothing.state", `Tools/trace.py --kind clothing`).
- Draft like League of Legends without bans: in turns with a timer, each hero once per match, the same category is
  fine, no trading. Teams are told apart only by the HP bar (red or blue).
- Attacks: left mouse a three-hit combo, right mouse and E specials, R the ultimate; built on the bought animation
  packs, damage lands on the hit frame. League-style indicators: hold to aim (arrow, circle, cone), release to cast.
- Every hit goes where the player looks at the moment it lands or leaves the hero's hand, not where he looked at
  the click (owner, 2026-10-29): swings, throws, shots, volleys, sweeps and a dash's shot, so turning while an attack
  plays hits whoever the player turns to and the hero never throws one way while his shot flies another. Only what
  moves the hero keeps the aim of its cast: a leap's landing spot and a dash's path. `HeroKit.follows` decides it for
  every kit, also new ones. Upwards and downwards as well, to the point under the crosshair (owner, 2026-10-29; the
  hero stands left of the camera's line, so a shot along the look from him flies 2.2 studs past what the crosshair is
  on): a shot up or down flies there, a swing strikes where the hero looks
  (`HeroCamera.aim`, `HeroKit.aimDirection`, enemies' heights in `HeroKit.inCone`), and every projectile stops at the
  first wall or floor; a dash's path stays on the ground. The same for every hero, also ones not yet built.
- Every hero's numbers (health, damage, ratios, speeds, ranges, cooldowns) are set against every other hero and his
  own class (owner, 2026-10-29), so they make sense together: compare key by key, his sustained damage (M1 per
  second) and his burst (his whole kit at once, also at point-blank range and on one target), and check his class's
  part: an Assassin the highest burst up close and little health, an Archer steady damage from range and the least
  health, paying for range with damage, a Tank the most health and little damage, and so on. Do this for every new
  hero and every change to one, test the doubtful cases in Play (a test dummy, hits counted), and write the
  comparison next to the numbers in `Config` (as Rowan's M1, E and R).
- Every hero dances every emote (`Config.Emotes`, owner, 2026-11-03), also every hero built later and every emote
  added later: the dances are lent to all heroes (`Motion.lend` in `Shared.Emote`), never made per hero, so a new hero
  needs no emote work of his own, only an R15 pack rig that `Motion.new` finds every joint of (no "[Motion] no joint"
  warning). Before a new hero is done, check in Play that he dances the emotes on the lobby's podium and in a match
  (G), his weapon included, and fix what is off in `Motion` or `Emote` for all heroes at once, never with an exception
  for one.
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
- Every file the owner has to use (imports, images, documents) is named by its full absolute path, never a relative
  one (owner, 2026-10-28).
- New Meshy models: first a concept (image-to-image) the owner approves, then 3D. Never generate without his go.
  Meshy is shared with RuneVille: never buy credits.
- Portraits (heroes and Masters, owner 2026-10-27) are made one way: Meshy image-to-image (nano-banana-pro) from a
  Play screenshot of the character with `Art/Portraits/shadowren.png` as the second reference for the painting style
  and the bust framing only. Every portrait stays its own: its pose, action, effects and background fit the hero and
  are never copied from another. Fixed are only the direction, chest and eyes towards the right of the picture or
  straight at the camera but never to the left, and the weapon in the hand he holds it in in the game; the prompt
  names both. A blue
  team copy is the red one recoloured locally (only the saturated reds, never the skin), so it matches exactly.
- Icons (abilities, shop items, ranks, menus) are always made the Cursor way (owner, 2026-10-28), never with Meshy;
  this is for icons only, other pictures such as the portraits keep their own way above:
  Cursor GenerateImage, one icon per image, square, with an existing icon of the set as the reference for the style
  (Shadowren's `Art/Icons/Shadowren/*.png` for abilities, a shop icon for shop items), on one flat key colour that
  the icon does not contain (pure green `#00FF00` for purple and red, magenta `#FF00FF` otherwise). The prompt asks
  for the same outline, glossy cartoon shading and colours as the reference and "a perfectly flat, solid pure ...
  background ... no shadow, no gradient, no texture, no vignette, nothing else in the image". Then
  `python3 Tools/key_icons.py <drawing> <out.png> [--glow] [--like <icon of the set>]` (`--glow` for soft slashes,
  smoke and trails) and `--check`; the green drawings stay in `Art/Icons/keyed/<set>/`. Every ability icon shows
  what that ability does in the hero's kit.
- A hero's attacks and poses are always chosen in a showroom in Play (owner, 2026-10-31: "dit moet onze standaard
  werkwijze worden"), never from dolls in Edit or from screenshots: the owner walks his own character over a platform
  high above the test ground between one clone of the hero per motion, each repeating it under a label with its
  number, length and name. The owner is always that hero himself there (owner, 2026-10-31: "dat ik ook zelf die
  poppetje ben"), his look, weapon and movement: a new hero first gets a test entry in `Config.Heroes` (look, pack,
  weapons, movement clips, a placeholder kit) and `TestHero` names him, and the showroom clones the player's own hero.
  Play goes there by itself (owner, 2026-10-31): the Workspace attributes `Match` and `TestGround` ticked,
  `TestMinions` unticked, `TestHero` set and `TestShowroom` listing the clips ("23-25, 35-68" or "all"), built by
  `src/client/Showroom.luau` on every spawn. The older `Tools/Showroom/` scripts do the same from the command bar.
- Every picture a menu page or the HUD can show is loaded by the loading screen, so a page is complete the first time
  it opens (owner, 2026-10-28 and 2026-10-29). `src/client/Pictures.luau` collects every `rbxassetid://` in
  `Shared.Config` and `Shared.Assets`: a new or replaced picture's id goes there (with an uploaded replacement, swap
  the id in place), never written into a page's own module, and a new sound in `Assets` goes into its `SOUNDS`.
- Keys only in the macOS Keychain. Third-party assets need a recorded source and licence (`Docs/Third_Party.md`).
- Nothing the owner or an agent made may ever be lost or put back to an older version (owner, 2026-10-28):
  - Change code and docs only with the editor's edit tools (StrReplace, Write), never with scripts, `sed` or `cp` over
    a file: Cursor's checkpoints only know the edit tools' changes, and restoring one puts every file back to the state
    of its last tool edit, dropping what scripts changed after it (17:35 on 2026-10-28).
  - `Tools/snapshot.sh` records the code under `refs/snapshots/` after every agent turn (a Cursor `stop` hook in
    `~/.cursor/hooks.json`) without touching the branch or any file; run it yourself before anything risky. When a
    file has lost work, take it back from the latest snapshot that has it (`Tools/snapshot.sh list`, `git show
    <snapshot>:<path>`), never from a reconstruction, and first compare every file so nothing newer is overwritten.
  - Never restore, check out or copy files over the working tree without first showing the owner what would change.

## Tools
- Rojo 7.7.1, StyLua and selene through Rokit (`~/.rokit/bin`): `rojo serve`, `stylua src`, `selene src`.
- `Art/Models/` holds the Meshy GLBs; `Art/Import/` is the staging folder for Import 3D (not in git).
- `Tools/kit_sheet.py` renders GLBs in Blender: `blender -b -P Tools/kit_sheet.py -- <folder> <out>`.
