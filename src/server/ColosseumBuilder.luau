-- Builds the colosseum at server start after the owner's designs 01, 02, 03 and 05 (Docs/Designs/Redesign_2026-10-26):
-- a round sand arena ringed by a low arena wall with braziers, stands, and an upper arcade with brazier columns,
-- festoons and banners; at each end the Master's throne on a dais before a backwall with the team's great banner,
-- between two knight statues, with four spawn pads and an armory stall; a plateau in the middle and cover along the
-- lanes. Every piece is a Meshy model from ServerStorage.ColosseumKit (imported through Import 3D, pivot at its bottom
-- centre, front towards -Z); only the sand floor, fire and light are Roblox's own.

local Lighting = game:GetService("Lighting")
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
-- Where each throne's dais front stands from the centre.
local BASE_DISTANCE = R - 25
-- The throne room's pieces in studs (design 02); the throne fits the Master at Config.Master.Scale.
local THRONE_HEIGHT = 12
-- The throne model's seat, as fractions of its height and of its depth from its middle (measured on the mesh).
local THRONE_SEAT_Y, THRONE_SEAT_Z = 0.231, -0.05
local DAIS_HEIGHT = 5
local STATUE_HEIGHT = 21
-- From the seat's top to a seated Master's root, per stud of his scale.
local SEATED_ROOT = 1.1
-- The pad model's height, and its top as a fraction of that.
local PAD_HEIGHT, PAD_TOP = 2.2, 0.915

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
	light.Range = size * 6
	light.Brightness = 1.4
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

local function isThroneSection(angle: number): boolean
	return angle == RED_ANGLE or angle == BLUE_ANGLE
end

-- The sand under the colosseum, with lighter and darker patches, and grass with cypresses and shrubs round it.
local function buildFloor(map: Folder)
	local floor = folder(map, "Floor")
	local sand = disc(floor, Vector3.zero, R + 30, 4, COLORS.Sand, Enum.Material.Sand)
	sand.Name = "Sand"
	sand:SetAttribute("Floor", true)
	disc(floor, Vector3.new(0, -0.05, 0), R + 600, 4, COLORS.Grass, Enum.Material.Grass).Name = "Grass"
	for _ = 1, 70 do
		local at = CFrame.new(polar(rng:NextNumber(0, 360), rng:NextNumber(R + 42, R + 150)))
			* CFrame.Angles(0, rng:NextNumber(0, 6.3), 0)
		if rng:NextNumber() < 0.55 then
			kit(floor, "cypress", at, byHeight("cypress", rng:NextNumber(14, 24)))
		else
			kit(floor, "shrub", at, byHeight("shrub", rng:NextNumber(3, 6)))
		end
	end
	for _ = 1, 24 do
		local a, d = rng:NextNumber(0, 360), rng:NextNumber(36, R - 14)
		local tone = if rng:NextNumber() < 0.5 then COLORS.SandDark else COLORS.SandLight
		for _ = 1, 3 do
			local offset = Vector3.new(rng:NextNumber(-6, 6), 0.04, rng:NextNumber(-6, 6))
			local patch = disc(floor, polar(a, d) + offset, rng:NextNumber(3, 8), 0.1, tone, Enum.Material.Sand)
			patch.CanCollide = false
			patch.CanQuery = false
			patch.CastShadow = false
		end
	end
end

-- The ring: the arena wall with braziers on its face, the stands behind it, and on the stands' back the upper arcade
-- with brazier columns, festoons and banners in the colour of the half they hang over (design 05).
local function buildRing(map: Folder)
	local wallFolder = folder(map, "ArenaWall")
	local standsFolder = folder(map, "Stands")
	local upperFolder = folder(map, "Upper")

	local wallScale = byWidth("arena_wall", chord(R) + 0.6)
	local wallSize = kitSize("arena_wall") * wallScale

	-- The stands are as wide as a section at their back, so neighbours close up there and overlap at the front.
	local standsFront = R + wallSize.Z + 0.5
	local standsSize = kitSize("stands")
	local standsScale = 0
	do
		local w = chord(standsFront)
		for _ = 1, 8 do
			w = chord(standsFront + standsSize.Z * w / standsSize.X)
		end
		standsScale = w / standsSize.X
	end
	local standsDepth = standsSize.Z * standsScale
	local standsHeight = standsSize.Y * standsScale
	local standsBack = standsFront + standsDepth

	-- The arcade stands on the stands' back wall, flush with its back.
	local arcadeSize = kitSize("arcade_upper")
	local arcadeScale = byWidth("arcade_upper", chord(standsBack) + 0.4)
	local arcadeDepth = arcadeSize.Z * arcadeScale
	local arcadeHeight = arcadeSize.Y * arcadeScale
	local arcadeMiddle = standsBack - arcadeDepth / 2
	local arcadeTop = standsHeight + arcadeHeight

	for i = 0, SECTIONS - 1 do
		local angle = i * STEP
		local gate = table.find(GATE_ANGLES, angle) ~= nil
		if gate then
			local gateScale = byWidth("gate", chord(R + 6) + 0.6)
			kit(wallFolder, "gate", ring(angle, R + kitSize("gate").Z * gateScale / 2), gateScale)
		elseif not isThroneSection(angle) then
			kit(wallFolder, "arena_wall", ring(angle, R + wallSize.Z / 2), wallScale)
		end
		kit(standsFolder, "stands", ring(angle, standsFront + standsDepth / 2), standsScale)
		kit(upperFolder, "arcade_upper", ring(angle, arcadeMiddle, standsHeight), arcadeScale)

		-- At every joint a brazier column on the arcade's top, two festoons across the section's front.
		local joint = angle + STEP / 2
		brazier(upperFolder, "column_brazier", ring(joint, arcadeMiddle, arcadeTop), 9)
		local festoonWidth = chord(arcadeMiddle) / 2 - 0.6
		local festoonScale = byWidth("festoon", festoonWidth)
		local festoonHeight = kitSize("festoon").Y * festoonScale
		for _, side in { -1, 1 } do
			local at = ring(angle, standsBack - arcadeDepth - 0.4, arcadeTop - festoonHeight - 1.2)
				* CFrame.new(side * festoonWidth / 2, 0, 0)
			kit(upperFolder, "festoon", at, festoonScale, false)
		end

		-- A banner on every third joint of the arcade, and wall braziers on the arena wall between the gates.
		if i % 3 == 1 then
			local team = if polar(joint, 1).Z > 0 then "blue" else "red"
			local bannerScale = byHeight("banner_" .. team, 15)
			kit(
				upperFolder,
				"banner_" .. team,
				ring(joint, standsBack - arcadeDepth - 0.8, standsHeight + 3),
				bannerScale,
				false
			)
		end
		if i % 2 == 0 and not gate and not isThroneSection(angle) then
			local bracket = kitSize("wall_brazier") * byHeight("wall_brazier", 4.2)
			brazier(wallFolder, "wall_brazier", ring(joint, R - bracket.Z / 2 + 0.3, 2.4), 4.2)
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
		for _, z in { -60, 60 } do
			kit(
				cover,
				"cover_blocks",
				CFrame.new(side * 16, 0, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), 0),
				byWidth("cover_blocks", 10)
			)
		end
	end
	for _ = 1, 10 do
		local at = polar(rng:NextNumber(0, 360), rng:NextNumber(34, R - 30))
		kit(
			cover,
			"rubble",
			CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 6.3), 0),
			byWidth("rubble", rng:NextNumber(3, 5))
		)
	end
end

export type Base = {
	throne: CFrame,
	spawn: CFrame,
	home: Vector3,
	pads: { CFrame },
	shop: CFrame,
}

-- One team's end (design 02): the dais and throne in the team's colour before a backwall with its great banner,
-- knight statues, braziers, cypresses and shrubs, the four spawn pads (design 03) and the armory stall.
local function buildBase(map: Folder, team: string): Base
	local suffix = if team == "Blue" then "_blue" else ""
	local bannerName = if team == "Blue" then "banner_blue" else "banner_red"
	local z = if team == "Blue" then BASE_DISTANCE else -BASE_DISTANCE
	local base = CFrame.lookAt(Vector3.new(0, 0, z), Vector3.zero)
	local area = folder(map, team .. "Base")
	local function at(x: number, y: number, back: number): CFrame
		return base * CFrame.new(x, y, back)
	end

	local daisScale = byHeight("dais" .. suffix, DAIS_HEIGHT)
	local daisDepth = kitSize("dais" .. suffix).Z * daisScale
	kit(area, "dais" .. suffix, at(0, 0, daisDepth / 2), daisScale)
	local throneScale = byHeight("throne" .. suffix, THRONE_HEIGHT)
	local throneDepth = kitSize("throne" .. suffix).Z * throneScale
	local throneBack = daisDepth - throneDepth / 2 - 2
	kit(area, "throne" .. suffix, at(0, DAIS_HEIGHT, throneBack), throneScale)

	-- The backwall closes the ring behind the throne and carries the great banner.
	local backScale = byWidth("backwall", chord(R) * 2)
	local backDepth = kitSize("backwall").Z * backScale
	local backFront = R - BASE_DISTANCE - 1
	kit(area, "backwall", at(0, 0, backFront + backDepth / 2), backScale)
	local bannerScale = byHeight(bannerName, 22)
	kit(area, bannerName, at(0, 7, backFront - kitSize(bannerName).Z * bannerScale / 2 - 0.2), bannerScale, false)

	for _, side in { -1, 1 } do
		kit(
			area,
			"statue",
			at(side * 14.5, 0, 9) * CFrame.Angles(0, math.rad(side * 8), 0),
			byHeight("statue", STATUE_HEIGHT)
		)
		brazier(area, "brazier_pillar", at(side * 6, DAIS_HEIGHT, 7), 6.5)
		brazier(area, "brazier_pillar", at(side * 22.5, 0, 6), 8)
		kit(area, "cypress", at(side * 28, 0, 14), byHeight("cypress", 14))
		kit(area, "shrub", at(side * 19, 0, 16), byHeight("shrub", 3.5))
		kit(area, "shrub", at(side * 33, 0, 9), byHeight("shrub", 3))
	end

	-- The four spawn pads, two either side of the throne along the arena's curve.
	local pads = {}
	local padScale = byHeight("pad", PAD_HEIGHT)
	for _, spot in { Vector3.new(-30, 0, 2), Vector3.new(30, 0, 2), Vector3.new(-55, 0, -14), Vector3.new(55, 0, -14) } do
		local cf = base * CFrame.new(spot)
		local pad = kit(area, "pad", cf, padScale)
		if pad then
			pad.Name = "SpawnPad"
			pad:SetAttribute("Team", team)
		end
		local top = cf.Position + Vector3.new(0, PAD_TOP * PAD_HEIGHT + 3, 0)
		table.insert(pads, CFrame.lookAt(top, Vector3.new(0, top.Y, 0)))
	end

	-- The armory stall by the wall, its counter towards the arena; a weapon rack and barrels beside it.
	local shop = at(-42, 0, 13) * CFrame.Angles(0, math.rad(-25), 0)
	kit(area, "armory_stall" .. suffix, shop, byHeight("armory_stall" .. suffix, 12))
	kit(
		area,
		"weapon_rack",
		shop * CFrame.new(10, 0, 1) * CFrame.Angles(0, math.rad(-10), 0),
		byHeight("weapon_rack", 7)
	)
	kit(area, "barrels", shop * CFrame.new(-9, 0, 2), byHeight("barrels", 4))

	local seatTop = at(0, DAIS_HEIGHT + THRONE_SEAT_Y * THRONE_HEIGHT, throneBack + THRONE_SEAT_Z * throneDepth)
	return {
		throne = seatTop * CFrame.new(0, SEATED_ROOT * Config.Master.Scale, 0),
		spawn = at(0, DAIS_HEIGHT, throneBack - throneDepth / 2 - 4),
		home = at(0, 0, daisDepth / 2).Position,
		pads = pads,
		shop = shop * CFrame.new(0, 0, -6),
	}
end

local function setupLighting()
	-- A bright, sunny afternoon with saturated colours, as in the designs.
	Lighting.ClockTime = 14.2
	Lighting.GeographicLatitude = 24
	Lighting.Brightness = 3.2
	Lighting.Ambient = Color3.fromRGB(120, 110, 104)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 160, 150)
	Lighting.EnvironmentDiffuseScale = 0.8
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.18
	atmosphere.Offset = 0.05
	atmosphere.Color = Color3.fromRGB(220, 230, 240)
	atmosphere.Decay = Color3.fromRGB(150, 170, 200)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 0.4
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
	grade.Saturation = 0.18
	grade.Contrast = 0.1
	grade.Brightness = 0.03
	grade.TintColor = Color3.fromRGB(255, 250, 240)
	local bloom = effect("BloomEffect", "MatchBloom") :: BloomEffect
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.4
end

export type Layout = {
	-- Each team's four spawn pads, as the spot a hero appears on, facing the centre.
	spawnPads: { [string]: { CFrame } },
	-- Where the Master stands up in front of his throne, and where his root sits when seated.
	masterSpawn: { [string]: CFrame },
	thrones: { [string]: CFrame },
	masterHome: { [string]: Vector3 },
	shops: { [string]: CFrame },
	map: Folder,
}

function ColosseumBuilder.build(): Layout
	for _, name in { "Baseplate", "SpawnLocation", "Map" } do
		local existing = Workspace:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end

	local map = Instance.new("Folder")
	map.Name = "Map"
	buildFloor(map)
	buildRing(map)
	buildCentre(map)
	buildCover(map)
	local layout: Layout = {
		spawnPads = {},
		masterSpawn = {},
		thrones = {},
		masterHome = {},
		shops = {},
		map = map,
	}
	for _, team in Config.TeamOrder do
		local base = buildBase(map, team)
		layout.spawnPads[team] = base.pads
		layout.masterSpawn[team] = base.spawn
		layout.thrones[team] = base.throne
		layout.masterHome[team] = base.home
		layout.shops[team] = base.shop
	end
	map.Parent = Workspace
	setupLighting()
	return layout
end

return ColosseumBuilder
