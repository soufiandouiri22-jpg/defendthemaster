-- Builds the colosseum at server start after the owner's designs 01, 02, 03 and 05 (Docs/Designs/Redesign_2026-10-26):
-- a round sand arena ringed by a low podium wall with banners and braziers, tiers of seats, and at their top an arcade
-- with brazier columns and red canopies; at each end the Master's throne on a dais before a backwall with the team's great banner,
-- between two knight statues, with four spawn pads and an armory stall; a plateau in the middle and cover along the
-- lanes. Every piece is a Meshy model from ServerStorage.ColosseumKit (imported through Import 3D, pivot at its bottom
-- centre, front towards -Z); only the sand floor, fire and light are Roblox's own.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local ColosseumBuilder = {}

local R = Config.Arena.Radius
-- The ring is cut in this many sections, each one arena wall, one stands piece and one arcade; section 0 faces east.
local SECTIONS = 36
local STEP = 360 / SECTIONS
-- The thrones stand at the north and south sections, the gates east and west.
local RED_ANGLE, BLUE_ANGLE = 90, 270
local GATE_ANGLES = { 0, 180 }
-- The stands' depth from the podium wall and their height at the back, and the banners' height on the podium wall.
local STANDS_DEPTH, STANDS_HEIGHT = 36, 32
local PODIUM_BANNER = 5.5
-- The sections with a doorway in the podium wall, two on each side between the gates and the thrones.
local DOOR_SECTIONS = { 4, 14, 22, 32 }
-- The throne room (design 02) grows with the Master: its sizes and spots are given for a Master at scale 1.8 and
-- multiplied by this.
local THRONE_ROOM = Config.Master.Scale / 1.8
local THRONE_HEIGHT = 12 * THRONE_ROOM
-- The throne model's seat, as fractions of its height and of its depth from its middle (measured on the mesh).
local THRONE_SEAT_Y, THRONE_SEAT_Z = 0.231, -0.05
local DAIS_HEIGHT = 5 * THRONE_ROOM
local STATUE_HEIGHT = 21 * THRONE_ROOM
-- From the seat's top to a seated Master's root, per stud of his scale.
local SEATED_ROOT = 1.1
-- The pad model's height, and its top as a fraction of that.
local PAD_HEIGHT, PAD_TOP = 2.2, 0.915
-- The Masters' collision group (MasterService puts them in it), and the group, also a pathfinding label, of the walls
-- only they meet: everything else, heroes and minions, their rays and their paths, goes through.
local MASTER, MASTER_BLOCK = "Master", "MasterBlock"
if not PhysicsService:IsCollisionGroupRegistered(MASTER) then
	PhysicsService:RegisterCollisionGroup(MASTER)
end
if not PhysicsService:IsCollisionGroupRegistered(MASTER_BLOCK) then
	PhysicsService:RegisterCollisionGroup(MASTER_BLOCK)
end
PhysicsService:CollisionGroupSetCollidable(MASTER_BLOCK, "Default", false)

local LIGHT = Config.Lighting.Presets[Config.Lighting.Preset]

local COLORS = {
	Sand = Color3.fromRGB(226, 190, 132),
	SandDark = Color3.fromRGB(214, 176, 120),
	SandLight = Color3.fromRGB(234, 202, 148),
	Paving = Color3.fromRGB(214, 190, 150),
	Grass = Color3.fromRGB(96, 150, 70),
	Fire = Color3.fromRGB(255, 160, 60),
}

local rng = Random.new(250)

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function polar(angle: number, radius: number, y: number?): Vector3
	local a = math.rad(angle)
	return Vector3.new(math.cos(a) * radius, y or 0, -math.sin(a) * radius)
end

-- On the ring at `angle`, `radius` from the centre and `y` up, its front (-Z) towards the centre.
local function ring(angle: number, radius: number, y: number?): CFrame
	local at = polar(angle, radius, y)
	return CFrame.lookAt(at, Vector3.new(0, at.Y, 0))
end

-- The width of a section at `radius`.
local function chord(radius: number): number
	return 2 * radius * math.sin(math.rad(STEP / 2))
end

-- The throne room's backwall stands just before the podium wall, its back corners on the wall's face: its width, and
-- its back's distance from the centre.
local function backwallSpan(): (number, number)
	local width = chord(R) * 2 * THRONE_ROOM
	return width, math.sqrt((R - 1) ^ 2 - (width / 2) ^ 2)
end

-- Whether a spot on the ring at `angle` is hidden behind a throne room's backwall.
local function behindBackwall(angle: number): boolean
	local width, back = backwallSpan()
	local half = math.deg(math.atan2(width / 2, back)) + 2
	for _, throne in { RED_ANGLE, BLUE_ANGLE } do
		if math.abs((angle - throne + 180) % 360 - 180) < half then
			return true
		end
	end
	return false
end

local function kitPiece(name: string): Model?
	local source = ServerStorage:FindFirstChild("ColosseumKit")
	local piece = source and source:FindFirstChild(name)
	if piece and piece:IsA("Model") and piece.PrimaryPart then
		return piece
	end
	warn("[ColosseumBuilder] ColosseumKit is missing", name)
	return nil
end

-- The size of a kit piece at its imported scale.
local function kitSize(name: string): Vector3
	local piece = kitPiece(name)
	return if piece then (piece.PrimaryPart :: BasePart).Size else Vector3.one
end

-- A kit piece scaled by `scale` with its pivot (bottom centre) at `at`. Decoration does not collide.
local function kit(parent: Instance, name: string, at: CFrame, scale: number, solid: boolean?): Model?
	local piece = kitPiece(name)
	if not piece then
		return nil
	end
	local m = piece:Clone()
	m:ScaleTo(scale)
	m:PivotTo(at)
	if solid == false then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
	end
	m.Parent = parent
	return m
end

-- Gives the team piece `m` the texture of its twin in the other team's colours, kit piece `other` (the same mesh), in
-- which the screens of the other team's players show it (client Side).
local function twin(m: Model?, other: string)
	local source = kitPiece(other)
	if not m or not source then
		return
	end
	local texture = (source.PrimaryPart :: MeshPart).TextureID
	for _, d in m:GetDescendants() do
		if d:IsA("MeshPart") and d.TextureID ~= texture then
			d:SetAttribute("OtherTexture", texture)
			CollectionService:AddTag(d, "TeamSwap")
		end
	end
end

-- A kit piece stretched to `size` studs, with its pivot (bottom centre) at `at`.
local function stretched(parent: Instance, name: string, at: CFrame, size: Vector3): Model?
	local piece = kitPiece(name)
	if not piece then
		return nil
	end
	local m = piece:Clone()
	local part = m.PrimaryPart :: BasePart
	local offset = part.PivotOffset
	part.PivotOffset = CFrame.new(offset.Position * size / part.Size) * offset.Rotation
	part.Size = size
	m:PivotTo(at)
	m.Parent = parent
	return m
end

-- The scale that makes a kit piece `height` studs tall, or `width` studs wide.
local function byHeight(name: string, height: number): number
	return height / kitSize(name).Y
end
local function byWidth(name: string, width: number): number
	return width / kitSize(name).X
end

-- The top middle of a placed model.
local function topOf(m: Model): Vector3
	local cf, size = m:GetBoundingBox()
	return cf.Position + Vector3.new(0, size.Y / 2, 0)
end

-- Fire and its light, rising from `position`.
local function flame(parent: Instance, position: Vector3, size: number)
	local holder = Instance.new("Part")
	holder.Name = "Flame"
	holder.Anchored = true
	holder.Size = Vector3.one * size
	holder.CFrame = CFrame.new(position)
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	local fire = Instance.new("Fire")
	fire.Size = size * 1.6
	fire.Heat = size * 2.2
	fire.Color = Color3.fromRGB(255, 150, 50)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
	fire.Parent = holder
	local light = Instance.new("PointLight")
	light.Color = COLORS.Fire
	light.Range = size * LIGHT.Flame.Range
	light.Brightness = LIGHT.Flame.Brightness
	light.Shadows = false
	light.Parent = holder
	holder.Parent = parent
end

-- A brazier kit piece with fire in its bowl.
local function brazier(parent: Instance, name: string, at: CFrame, height: number)
	local m = kit(parent, name, at, byHeight(name, height))
	if m then
		flame(parent, topOf(m) - Vector3.new(0, height * 0.04, 0), math.max(1.2, height * 0.22))
	end
end

local function disc(parent: Instance, center: Vector3, radius: number, thickness: number, color: Color3, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(thickness, radius * 2, radius * 2)
	p.CFrame = CFrame.new(center - Vector3.new(0, thickness / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- The sand under the colosseum, with lighter and darker patches, and grass with cypresses and shrubs round it.
local function buildFloor(map: Folder)
	local floor = folder(map, "Floor")
	local sand = disc(floor, Vector3.zero, R + 30, 4, COLORS.Sand, Enum.Material.Sand)
	sand.Name = "Sand"
	sand:SetAttribute("Floor", true)
	disc(floor, Vector3.new(0, -0.05, 0), R + 600, 4, COLORS.Grass, Enum.Material.Grass).Name = "Grass"
	for _ = 1, 70 do
		local at = CFrame.new(polar(rng:NextNumber(0, 360), rng:NextNumber(R + 62, R + 170)))
			* CFrame.Angles(0, rng:NextNumber(0, 6.3), 0)
		if rng:NextNumber() < 0.55 then
			kit(floor, "cypress", at, byHeight("cypress", rng:NextNumber(14, 24)))
		else
			kit(floor, "shrub", at, byHeight("shrub", rng:NextNumber(3, 6)))
		end
	end
	-- Each patch is three overlapping discs; no two discs may share a top where they overlap or they flicker, so the
	-- patches keep apart and their discs lie a little above one another.
	local patches: { Vector3 } = {}
	for _ = 1, 400 do
		if #patches == 24 then
			break
		end
		local at = polar(rng:NextNumber(0, 360), rng:NextNumber(36, R - 14))
		local clear = true
		for _, other in patches do
			if (other - at).Magnitude < 30 then
				clear = false
				break
			end
		end
		if not clear then
			continue
		end
		table.insert(patches, at)
		local tone = if rng:NextNumber() < 0.5 then COLORS.SandDark else COLORS.SandLight
		for k = 1, 3 do
			local offset = Vector3.new(rng:NextNumber(-6, 6), 0.06 * k, rng:NextNumber(-6, 6))
			local patch = disc(floor, at + offset, rng:NextNumber(3, 8), 0.1, tone, Enum.Material.Sand)
			patch.CanCollide = false
			patch.CanQuery = false
			patch.CastShadow = false
		end
	end
end

-- The ring as in the first version and design 01: a low podium wall round the sand with banners, wall braziers and
-- doorways; behind it the stands, tiers of seats rising to a walk at the top; there the outer arcade with brazier
-- columns, and red canopies on posts leaning out over the top tiers. Each doorway's spot on the sand, facing the centre,
-- goes into `doors` under the team whose half it is on.
local function buildRing(map: Folder, doors: { [string]: { CFrame } })
	local wallFolder = folder(map, "ArenaWall")
	local standsFolder = folder(map, "Stands")
	local upperFolder = folder(map, "Upper")

	local wallScale = byWidth("arena_wall", chord(R) + 0.6)
	local wallSize = kitSize("arena_wall") * wallScale

	-- The stands are the kit's flight of stairs stretched into tiers of seats, as wide as a section at their back so
	-- neighbours close up there.
	local standsFront = R + wallSize.Z - 0.5
	local standsBack = standsFront + STANDS_DEPTH
	local standsSize = Vector3.new(chord(standsBack) + 0.4, STANDS_HEIGHT, STANDS_DEPTH)

	-- The arcade, two to a section, on the walk at the stands' back.
	local arcadeScale = byWidth("arcade_upper", chord(standsBack) / 2 + 0.3)
	local arcadeSize = kitSize("arcade_upper") * arcadeScale
	local arcadeMiddle = standsBack - arcadeSize.Z / 2
	local arcadeTop = STANDS_HEIGHT + arcadeSize.Y

	local canopyScale = byWidth("canopy", chord(standsBack - arcadeSize.Z) + 0.2)
	local canopySize = kitSize("canopy") * canopyScale

	for i = 0, SECTIONS - 1 do
		local angle = i * STEP
		local joint = angle + STEP / 2
		local gate = table.find(GATE_ANGLES, angle) ~= nil
		if gate then
			local gateScale = byWidth("gate", chord(R + 6) + 0.6)
			kit(wallFolder, "gate", ring(angle, R + kitSize("gate").Z * gateScale / 2), gateScale)
		else
			kit(wallFolder, "arena_wall", ring(angle, R + wallSize.Z / 2), wallScale)
		end
		stretched(standsFolder, "stairs", ring(angle, standsFront + STANDS_DEPTH / 2), standsSize)

		for _, side in { -0.25, 0.25 } do
			kit(upperFolder, "arcade_upper", ring(angle + side * STEP, arcadeMiddle, STANDS_HEIGHT), arcadeScale)
		end
		brazier(upperFolder, "column_brazier", ring(joint, arcadeMiddle, arcadeTop), 7)
		kit(
			upperFolder,
			"canopy",
			ring(angle, standsBack - arcadeSize.Z - canopySize.Z / 2, STANDS_HEIGHT),
			canopyScale,
			false
		)

		-- On the podium wall's face: a banner in the colour of its half on every third section, a doorway on four,
		-- and wall braziers at the joints between them; none behind a throne room.
		if not gate and not behindBackwall(angle) then
			local face = R - 0.2
			if i % 3 == 0 then
				local team = if polar(angle, 1).Z > 0 then "blue" else "red"
				local bannerScale = byHeight("banner_" .. team, PODIUM_BANNER)
				local bannerDepth = kitSize("banner_" .. team).Z * bannerScale
				twin(
					kit(
						wallFolder,
						"banner_" .. team,
						ring(angle, face - bannerDepth / 2, wallSize.Y - PODIUM_BANNER - 0.4),
						bannerScale,
						false
					),
					if team == "blue" then "banner_red" else "banner_blue"
				)
			elseif table.find(DOOR_SECTIONS, i) then
				local doorScale = byHeight("wall_door", wallSize.Y - 0.8)
				local doorDepth = kitSize("wall_door").Z * doorScale
				kit(wallFolder, "wall_door", ring(angle, R - doorDepth / 2 + 0.4), doorScale)
				local team = if polar(angle, 1).Z > 0 then "Blue" else "Red"
				table.insert(doors[team], ring(angle, R - doorDepth - 2))
			end
			if i % 2 == 0 and not behindBackwall(joint) then
				local bracket = kitSize("wall_brazier") * byHeight("wall_brazier", 4.2)
				brazier(wallFolder, "wall_brazier", ring(joint, R - bracket.Z / 2 + 0.3, 2.4), 4.2)
			end
		end
	end

	-- Invisible walls keep everyone on the sand.
	local bounds = folder(map, "Bounds")
	for i = 0, 63 do
		local angle = (i + 0.5) * 360 / 64
		local wall = Instance.new("Part")
		wall.Name = "ArenaBound"
		wall.Anchored = true
		wall.Size = Vector3.new(2 * (R + 1) * math.tan(math.rad(360 / 128)) + 0.5, 80, 2)
		wall.CFrame = ring(angle, R + 1, 40)
		wall.Transparency = 1
		wall.CastShadow = false
		wall.Parent = bounds
	end
end

-- The plateau in the middle on a paved ring, with crates and barrels round it.
local function buildCentre(map: Folder)
	local centre = folder(map, "Centre")
	disc(centre, Vector3.new(0, 0.1, 0), 26, 0.3, COLORS.Paving, Enum.Material.Pavement).CastShadow = false
	kit(centre, "plateau", CFrame.new(0, 0, 0), byWidth("plateau", 30))
	for k, spot in
		{ Vector3.new(26, 0, 17), Vector3.new(-26, 0, -17), Vector3.new(-26, 0, 17), Vector3.new(26, 0, -17) }
	do
		local yaw = CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
		if k <= 2 then
			kit(centre, "crates", CFrame.new(spot) * yaw, byHeight("crates", 7))
		else
			kit(centre, "barrels", CFrame.new(spot) * yaw, byHeight("barrels", 4))
		end
	end
end

-- Cover along the lanes (design 01): an arc of low walls either side of the plateau, pillars, rubble and ruins.
local function buildCover(map: Folder)
	local cover = folder(map, "Cover")
	for _, side in { -1, 1 } do
		for _, offset in { -24, 0, 24 } do
			local angle = (if side == 1 then 0 else 180) + offset
			kit(cover, "cover_arc", ring(angle, 66), byWidth("cover_arc", 22))
		end
		kit(
			cover,
			"pillar_broken",
			CFrame.new(side * 44, 0, -46) * CFrame.Angles(0, math.rad(side * 30), 0),
			byHeight("pillar_broken", 10)
		)
		kit(
			cover,
			"pillar_broken",
			CFrame.new(side * 46, 0, 44) * CFrame.Angles(0, math.rad(side * -50), 0),
			byHeight("pillar_broken", 9)
		)
		kit(cover, "pillar_whole", ring(if side == 1 then 0 else 180, 96), byHeight("pillar_whole", 15))
		kit(cover, "cover_ruin", ring(if side == 1 then 30 else 150, 98), byWidth("cover_ruin", 16))
		kit(cover, "cover_ruin", ring(if side == 1 then -30 else 210, 98), byWidth("cover_ruin", 16))
		for _, z in { -48, 48 } do
			kit(
				cover,
				"cover_blocks",
				CFrame.new(side * 16, 0, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), 0),
				byWidth("cover_blocks", 10)
			)
		end
	end
end

-- A flat kit piece `width` studs wide on `at`, sunk into the sand so its top stands `top` studs above it.
local function sunk(parent: Instance, name: string, at: CFrame, width: number, top: number): Model?
	local scale = byWidth(name, width)
	return kit(parent, name, at * CFrame.new(0, top - kitSize(name).Y * scale, 0), scale)
end

-- The spike tile's holes, as shares of its width and depth from its middle, and how high its top and its spikes'
-- tips stand above the sand at rest (in the sand, just under it).
local SPIKE_HOLES = 0.32
local SPIKE_TOP, SPIKE_REST = 0.25, -0.05
-- How wide a spike is.
local SPIKE_WIDTH = 1.1

-- The arena's traps and ways (Config.Spikes, FireGrates, NetStatues, RuneGates, JumpPads) in Map.Features, one folder
-- per kind, which their services and views find by name: a spike tile's spikes (its "Spikes" model) wait in the sand
-- under its holes; a gate carries its name ("Gate"); a statue faces the spot it aims at, and a pad carries its number
-- in Config.JumpPads.Spots ("Index") and where it throws ("To"), its arrows pointing there.
local function buildFeatures(map: Folder)
	local features = folder(map, "Features")
	if Config.Spikes.Enabled then
		local tiles = folder(features, "Spikes")
		local width, height = Config.Spikes.Width, Config.Spikes.Height
		for _, spot in Config.Spikes.Spots do
			local tile = Instance.new("Model")
			tile.Name = "SpikeTile"
			local frame = CFrame.new(spot.At) * CFrame.Angles(0, math.rad(spot.Turn), 0)
			local piece = sunk(tile, "spike_tile", frame, width, SPIKE_TOP)
			local spikes = Instance.new("Model")
			spikes.Name = "Spikes"
			local size = if piece then (piece.PrimaryPart :: BasePart).Size else Vector3.new(width, 0, width)
			for _, x in { -1, 0, 1 } do
				for _, z in { -1, 0, 1 } do
					local foot = frame
						* Vector3.new(x * size.X * SPIKE_HOLES, SPIKE_REST - height, z * size.Z * SPIKE_HOLES)
					local spike = stretched(
						spikes,
						"spike",
						CFrame.new(foot) * CFrame.Angles(0, rng:NextNumber(0, 6.3), 0),
						Vector3.new(SPIKE_WIDTH, height, SPIKE_WIDTH)
					)
					if spike then
						for _, d in spike:GetDescendants() do
							if d:IsA("BasePart") then
								d.CanCollide = false
								d.CanQuery = false
								d.CanTouch = false
							end
						end
					end
				end
			end
			spikes.Parent = tile
			tile.Parent = tiles
		end
	end
	if Config.FireGrates.Enabled then
		local grates = folder(features, "FireGrates")
		for _, at in Config.FireGrates.Spots do
			local turn = CFrame.Angles(0, rng:NextNumber(0, 6.3), 0)
			sunk(grates, "fire_grate", CFrame.new(at) * turn, Config.FireGrates.Width, 0.35)
		end
	end
	if Config.NetStatues.Enabled then
		local statues = folder(features, "NetStatues")
		for _, spot in Config.NetStatues.Spots do
			local front = CFrame.lookAt(spot.At, spot.Faces)
			kit(statues, "net_statue", front, byHeight("net_statue", Config.NetStatues.Height))
		end
	end
	if Config.RuneGates.Enabled then
		local gates = folder(features, "RuneGates")
		for name, spot in Config.RuneGates.Spots do
			local gate = sunk(gates, "rune_gate", CFrame.new(spot.At), Config.RuneGates.Width, 0.12)
			if gate then
				gate:SetAttribute("Gate", name)
			end
		end
	end
	if Config.JumpPads.Enabled then
		local pads = folder(features, "JumpPads")
		for i, spot in Config.JumpPads.Spots do
			-- The kit's jump_pad has its arrows along its -X: turned a quarter so they point where it throws.
			local facing = CFrame.lookAt(spot.At, spot.To) * CFrame.Angles(0, math.rad(-90), 0)
			local pad = sunk(pads, "jump_pad", facing, Config.JumpPads.Width, 1.2)
			if pad then
				pad:SetAttribute("Index", i)
				pad:SetAttribute("To", spot.To)
			end
		end
	end
end

-- Rubble strewn over the sand, a few studs clear of everything else placed on it.
local function scatterRubble(map: Folder)
	local taken: { { at: Vector3, radius: number } } = {}
	for _, name in { "Centre", "Cover", "BlueBase", "RedBase", "Features" } do
		for _, m in (map:FindFirstChild(name) :: Folder):GetDescendants() do
			if m:IsA("Model") and m.Parent and m.Parent:IsA("Folder") then
				local cf, size = m:GetBoundingBox()
				table.insert(taken, { at = cf.Position * Vector3.new(1, 0, 1), radius = math.max(size.X, size.Z) / 2 })
			end
		end
	end
	local cover = map:FindFirstChild("Cover") :: Folder
	local placed = 0
	for _ = 1, 400 do
		if placed == 10 then
			break
		end
		local at = polar(rng:NextNumber(0, 360), rng:NextNumber(34, R - 30))
		local width = rng:NextNumber(3, 5)
		local clear = true
		for _, t in taken do
			if (t.at - at).Magnitude < t.radius + width / 2 + 3 then
				clear = false
				break
			end
		end
		if clear then
			kit(cover, "rubble", CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 6.3), 0), byWidth("rubble", width))
			table.insert(taken, { at = at, radius = width / 2 })
			placed += 1
		end
	end
end

export type Base = {
	throne: CFrame,
	spawn: CFrame,
	home: Vector3,
	-- The middle of the dais' front, on the sand.
	front: Vector3,
	pads: { CFrame },
	-- Where a hero stands to buy at each of the base's armory stalls.
	shops: { CFrame },
}

-- One team's end (design 02): the dais and throne in the team's colour before a backwall with its great banner,
-- knight statues, braziers, cypresses and shrubs, the four spawn pads (design 03) and the armory stall. The throne
-- room is laid out from the backwall forward; `at` places from the dais' front middle, `back` away from the centre.
local function buildBase(map: Folder, team: string): Base
	local suffix = if team == "Blue" then "_blue" else ""
	local otherSuffix = if team == "Blue" then "" else "_blue"
	local bannerName = if team == "Blue" then "banner_blue" else "banner_red"
	local otherBanner = if team == "Blue" then "banner_red" else "banner_blue"
	local area = folder(map, team .. "Base")
	local s = THRONE_ROOM

	local backWidth, backBack = backwallSpan()
	local backScale = byWidth("backwall", backWidth)
	local backDepth = kitSize("backwall").Z * backScale
	local daisScale = byHeight("dais" .. suffix, DAIS_HEIGHT)
	local daisDepth = kitSize("dais" .. suffix).Z * daisScale
	local daisFront = backBack - backDepth - 1 - daisDepth

	local sign = if team == "Blue" then 1 else -1
	local base = CFrame.lookAt(Vector3.new(0, 0, sign * daisFront), Vector3.zero)
	local function at(x: number, y: number, back: number): CFrame
		return base * CFrame.new(x, y, back)
	end
	local backFront = daisDepth + 1

	-- The backwall stands before the podium wall and carries the great banner.
	kit(area, "backwall", at(0, 0, backFront + backDepth / 2), backScale)
	local bannerScale = byHeight(bannerName, 22 * s)
	twin(
		kit(
			area,
			bannerName,
			at(0, 7 * s, backFront - kitSize(bannerName).Z * bannerScale / 2 - 0.2),
			bannerScale,
			false
		),
		otherBanner
	)

	twin(kit(area, "dais" .. suffix, at(0, 0, daisDepth / 2), daisScale), "dais" .. otherSuffix)
	local throneScale = byHeight("throne" .. suffix, THRONE_HEIGHT)
	local throneDepth = kitSize("throne" .. suffix).Z * throneScale
	local throneBack = daisDepth - throneDepth / 2 - 2 * s
	twin(kit(area, "throne" .. suffix, at(0, DAIS_HEIGHT, throneBack), throneScale), "throne" .. otherSuffix)

	for _, side in { -1, 1 } do
		kit(
			area,
			"statue",
			at(side * 14.5 * s, 0, 9 * s) * CFrame.Angles(0, math.rad(side * 8), 0),
			byHeight("statue", STATUE_HEIGHT)
		)
		brazier(area, "brazier_pillar", at(side * 6 * s, DAIS_HEIGHT, 7 * s), 6.5 * s)
		brazier(area, "brazier_pillar", at(side * 22.5 * s, 0, 6 * s), 8 * s)
		kit(area, "cypress", at(side * 28 * s, 0, 14 * s), byHeight("cypress", 14 * s))
		kit(area, "shrub", at(side * 19 * s, 0, 16 * s), byHeight("shrub", 3.5 * s))
		kit(area, "shrub", at(side * 30 * s, 0, 4 * s), byHeight("shrub", 3 * s))
	end

	-- The gap between the dais and each statue and the room behind the statue, up to the backwall: a hero fits
	-- through, the Master would wedge himself in, so walls only he meets close it.
	local daisHalf = kitSize("dais" .. suffix).X * daisScale / 2
	local statueSize = kitSize("statue") * byHeight("statue", STATUE_HEIGHT)
	local turn = math.rad(8)
	local statueHalfX = statueSize.X / 2 * math.cos(turn) + statueSize.Z / 2 * math.sin(turn)
	local statueHalfZ = statueSize.X / 2 * math.sin(turn) + statueSize.Z / 2 * math.cos(turn)
	local blockFront = 9 * s - statueHalfZ - 1
	local blockInner, blockOuter = daisHalf - 0.5, 14.5 * s + statueHalfX + 1
	local function masterBlock(fromX: number, toX: number, fromBack: number)
		local block = Instance.new("Part")
		block.Name = "MasterBlock"
		block.Anchored = true
		block.Transparency = 1
		block.CastShadow = false
		block.CanTouch = false
		block.CollisionGroup = MASTER_BLOCK
		block.Size = Vector3.new(toX - fromX, 40, backFront - fromBack)
		block.CFrame = at((fromX + toX) / 2, 20, (fromBack + backFront) / 2)
		local modifier = Instance.new("PathfindingModifier")
		modifier.Label = MASTER_BLOCK
		modifier.PassThrough = true
		modifier.Parent = block
		block.Parent = area
	end
	for _, side in { -1, 1 } do
		masterBlock(
			math.min(side * blockInner, side * blockOuter),
			math.max(side * blockInner, side * blockOuter),
			blockFront
		)
	end
	-- And the dais beside and behind the throne, from its front back: he would wedge himself in there too. He
	-- stands up in front of it and sits down on it without walking (MasterService).
	masterBlock(-blockInner, blockInner, throneBack - throneDepth / 2)

	-- The four spawn pads, two either side of the throne room along the arena's curve.
	local pads = {}
	local padScale = byHeight("pad", PAD_HEIGHT)
	for _, spot in
		{ Vector3.new(-46, 0, -12), Vector3.new(46, 0, -12), Vector3.new(-70, 0, -26), Vector3.new(70, 0, -26) }
	do
		local cf = base * CFrame.new(spot)
		local pad = kit(area, "pad", cf, padScale)
		if pad then
			pad.Name = "SpawnPad"
			pad:SetAttribute("Team", team)
		end
		local top = cf.Position + Vector3.new(0, PAD_TOP * PAD_HEIGHT + 3, 0)
		table.insert(pads, CFrame.lookAt(top, Vector3.new(0, top.Y, 0)))
	end

	-- An armory stall either side of the throne room, so every hero has one close by; each has its counter towards
	-- the arena, a weapon rack on the throne's side and barrels on the wall's.
	local shops = {}
	for _, side in { -1, 1 } do
		local shop = at(side * 66, 0, 18) * CFrame.Angles(0, math.rad(side * 25), 0)
		twin(
			kit(area, "armory_stall" .. suffix, shop, byHeight("armory_stall" .. suffix, 12)),
			"armory_stall" .. otherSuffix
		)
		kit(
			area,
			"weapon_rack",
			shop * CFrame.new(-side * 10, 0, 1) * CFrame.Angles(0, math.rad(side * 10), 0),
			byHeight("weapon_rack", 7)
		)
		kit(area, "barrels", shop * CFrame.new(side * 10, 0, -2), byHeight("barrels", 4))
		table.insert(shops, shop * CFrame.new(0, 0, -6))
	end

	local seatTop = at(0, DAIS_HEIGHT + THRONE_SEAT_Y * THRONE_HEIGHT, throneBack + THRONE_SEAT_Z * throneDepth)
	return {
		throne = seatTop * CFrame.new(0, SEATED_ROOT * Config.Master.Scale, 0),
		spawn = at(0, DAIS_HEIGHT, throneBack - throneDepth / 2 - 4 * s),
		home = at(0, 0, daisDepth / 2).Position,
		front = base.Position,
		pads = pads,
		shops = shops,
	}
end

-- The arena's light: Config.Lighting's preset.
local function setupLighting()
	local preset = LIGHT
	Lighting.ClockTime = preset.ClockTime
	Lighting.GeographicLatitude = 24
	Lighting.Brightness = preset.Brightness
	Lighting.Ambient = preset.Ambient
	Lighting.OutdoorAmbient = preset.OutdoorAmbient
	Lighting.ColorShift_Top = preset.ColorShiftTop
	Lighting.EnvironmentDiffuseScale = preset.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = preset.EnvironmentSpecularScale
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = preset.ShadowSoftness
	Lighting.ExposureCompensation = preset.Exposure

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	for name, value in preset.Atmosphere do
		(atmosphere :: any)[name] = value
	end
	atmosphere.Parent = Lighting

	local function effect(className: string, name: string): Instance
		local existing = Lighting:FindFirstChild(name)
		if existing then
			return existing
		end
		local created = Instance.new(className)
		created.Name = name
		created.Parent = Lighting
		return created
	end
	local grade = effect("ColorCorrectionEffect", "MatchGrade") :: ColorCorrectionEffect
	grade.Saturation = preset.Grade.Saturation
	grade.Contrast = preset.Grade.Contrast
	grade.Brightness = preset.Grade.Brightness
	grade.TintColor = preset.Grade.Tint
	local bloom = effect("BloomEffect", "MatchBloom") :: BloomEffect
	bloom.Intensity = preset.Bloom.Intensity
	bloom.Size = preset.Bloom.Size
	bloom.Threshold = preset.Bloom.Threshold
end

-- Pieces that belong on or against another piece, as "lower/upper" name pairs; every other overlap is a mistake.
local MAY_TOUCH = {
	["dais/throne"] = true,
	["dais/brazier_pillar"] = true,
	["backwall/banner"] = true,
}

local function touchKey(a: string, b: string): string
	local function family(name: string): string
		return (name:gsub("_blue$", ""):gsub("_red$", ""))
	end
	return family(a) .. "/" .. family(b)
end

-- Warns about every free-standing piece (in the bases, the centre, the cover, the grounds) that stands in another one
-- or in the ring. The ring's own pieces overlap each other on purpose and are not compared among themselves.
local function checkOverlaps(map: Folder): number
	local function models(names: { string }): { Model }
		local list = {}
		for _, name in names do
			local f = map:FindFirstChild(name)
			for _, child in if f then f:GetChildren() else {} do
				if child:IsA("Model") then
					table.insert(list, child)
				end
			end
		end
		return list
	end
	local pieces = models({ "BlueBase", "RedBase", "Centre", "Cover", "Floor" })
	local ringPieces = models({ "ArenaWall", "Stands", "Upper" })
	local found = 0
	for i, a in pieces do
		local cfA, sizeA = a:GetBoundingBox()
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		local others = table.clone(ringPieces)
		for j = i + 1, #pieces do
			table.insert(others, pieces[j])
		end
		params.FilterDescendantsInstances = others
		-- A tenth in from every side, so pieces that only stand close are not reported.
		for _, hit in Workspace:GetPartBoundsInBox(cfA, sizeA * 0.9, params) do
			local b = hit:FindFirstAncestorWhichIsA("Model")
			if b and not MAY_TOUCH[touchKey(a.Name, b.Name)] and not MAY_TOUCH[touchKey(b.Name, a.Name)] then
				found += 1
				warn(
					string.format(
						"[ColosseumBuilder] %s at %s stands in %s at %s",
						a.Name,
						tostring(a:GetPivot().Position),
						b.Name,
						tostring(b:GetPivot().Position)
					)
				)
			end
		end
	end
	return found
end

export type Layout = {
	-- Each team's four spawn pads, as the spot a hero appears on, facing the centre.
	spawnPads: { [string]: { CFrame } },
	-- Where the Master stands up in front of his throne, and where his root sits when seated.
	masterSpawn: { [string]: CFrame },
	thrones: { [string]: CFrame },
	masterHome: { [string]: Vector3 },
	-- The middle of each throne room's dais front, on the sand.
	daisFront: { [string]: Vector3 },
	-- Each team's two armory stalls, as the spot a hero stands to buy.
	shops: { [string]: { CFrame } },
	-- The spots on the sand before each team's two doorways, facing the centre, where its minions come out.
	minionDoors: { [string]: { CFrame } },
	map: Folder,
}

local function emptyLayout(): Layout
	for _, name in { "Baseplate", "SpawnLocation", "Map" } do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	local map = Instance.new("Folder")
	map.Name = "Map"
	return {
		spawnPads = {},
		masterSpawn = {},
		thrones = {},
		masterHome = {},
		daisFront = {},
		shops = {},
		minionDoors = { Blue = {}, Red = {} },
		map = map,
	}
end

function ColosseumBuilder.build(): Layout
	local layout = emptyLayout()
	local map = layout.map
	buildFloor(map)
	buildRing(map, layout.minionDoors)
	buildCentre(map)
	buildCover(map)
	for _, team in Config.TeamOrder do
		local base = buildBase(map, team)
		layout.spawnPads[team] = base.pads
		layout.masterSpawn[team] = base.spawn
		layout.thrones[team] = base.throne
		layout.masterHome[team] = base.home
		layout.daisFront[team] = base.front
		layout.shops[team] = base.shops
	end
	buildFeatures(map)
	scatterRubble(map)
	map.Parent = Workspace
	print("[ColosseumBuilder] overlapping pieces:", checkOverlaps(map))
	setupLighting()
	return layout
end

-- Studio's test ground (TestGround): both throne rooms on open sand as they stand in the colosseum, and the Blue
-- heroes' spawn on the sand before the Red one, `TEST_SPAWN` studs out from its dais, beyond its Master's zone. Blue's
-- armory is that spawn, with its stall just behind it facing the Red throne, so the HUD and the armory work as in a
-- match.
local TEST_SPAWN = 72

function ColosseumBuilder.buildTestGround(): Layout
	local layout = emptyLayout()
	local map = layout.map
	local floor = folder(map, "Floor")
	local sand = disc(floor, Vector3.zero, R + 30, 4, COLORS.Sand, Enum.Material.Sand)
	sand.Name = "Sand"
	sand:SetAttribute("Floor", true)
	disc(floor, Vector3.new(0, -0.05, 0), R + 600, 4, COLORS.Grass, Enum.Material.Grass).Name = "Grass"

	for _, team in Config.TeamOrder do
		local base = buildBase(map, team)
		layout.spawnPads[team] = base.pads
		layout.masterSpawn[team] = base.spawn
		layout.thrones[team] = base.throne
		layout.masterHome[team] = base.home
		layout.daisFront[team] = base.front
		layout.shops[team] = base.shops
	end

	local front = layout.daisFront.Red
	local spot = front - front.Unit * TEST_SPAWN
	local facing = Vector3.new(front.X, 0, front.Z)
	local pads = {}
	for _, side in { -6, 6 } do
		local at = spot + Vector3.new(side, 3, 0)
		table.insert(pads, CFrame.lookAt(at, facing + Vector3.new(side, 3, 0)))
	end
	layout.spawnPads.Blue = pads
	local shop = CFrame.lookAt(spot, facing)
	layout.shops.Blue = { shop }
	kit(folder(map, "TestArmory"), "armory_stall_blue", shop * CFrame.new(0, 0, 6), byHeight("armory_stall_blue", 12))
	-- Where they stand in the colosseum, to be tried out.
	buildFeatures(map)

	map.Parent = Workspace
	setupLighting()
	return layout
end

-- The kit's helpers and the arena's light, for the lobby's hall (Lobby.LobbyBuilder).
ColosseumBuilder.Kit = {
	kit = kit,
	kitSize = kitSize,
	byHeight = byHeight,
	byWidth = byWidth,
	topOf = topOf,
	flame = flame,
	brazier = brazier,
	disc = disc,
	folder = folder,
	colors = COLORS,
}
ColosseumBuilder.setupLighting = setupLighting

return ColosseumBuilder
