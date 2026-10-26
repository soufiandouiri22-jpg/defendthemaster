-- Builds the team minions, the rock creatures of concept G (Art/Concepts/Minions/minions_concept_G_rock.jpg), from
-- Roblox parts: a carved stone cube with bevelled, chipped edges and cracks, two block ears and four stubby feet, an
-- angry face, and glowing crystals in the team's colour on its head and in its side; the spitter's crystals are bigger
-- and light up the sand round it. The body, ears and feet are one union in the team's stone; the rest is welded on.
-- Each model's pivot is its bottom centre and its face looks towards -Z, as the kit's pieces do. Each kind's template is
-- built once and cloned.

local GeometryService = game:GetService("GeometryService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local MinionModel = {}

export type Kind = "Melee" | "Spitter"

-- The body's size, its edges' bevel, and how high it stands on its feet (studs; a hero is about 5.2 tall).
local BODY = Vector3.new(3.4, 3.6, 3.3)
local BEVEL = 0.32
local BODY_LIFT = 0.6

local EYE_WHITE = Color3.fromRGB(248, 244, 240)
local PUPIL = Color3.fromRGB(24, 18, 18)
local FANG = Color3.fromRGB(240, 228, 210)
local MOUTH = Color3.fromRGB(34, 26, 28)

-- Per team: the stone, and the crystals' glow.
local STONE = {
	Blue = Color3.fromRGB(84, 104, 140),
	Red = Color3.fromRGB(128, 50, 38),
}
local CRYSTAL = {
	Blue = Color3.fromRGB(40, 118, 255),
	Red = Color3.fromRGB(255, 44, 34),
}
local STONE_MATERIAL = Enum.Material.Slate

local function newPart(props: { [string]: any }, className: string?): BasePart
	local p = Instance.new(className or "Part") :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- The parts of a box `size` centred on `cf` with every edge bevelled by `bevel`: three crossing blocks and a block
-- turned 45 degrees along each edge.
local function bevelledBox(cf: CFrame, size: Vector3, bevel: number): { BasePart }
	local b = math.min(bevel, size.X / 2, size.Y / 2, size.Z / 2)
	local inner = size - Vector3.one * 2 * b
	local d = b * math.sqrt(2)
	local parts = {
		newPart({ Size = Vector3.new(size.X, inner.Y, inner.Z), CFrame = cf }),
		newPart({ Size = Vector3.new(inner.X, size.Y, inner.Z), CFrame = cf }),
		newPart({ Size = Vector3.new(inner.X, inner.Y, size.Z), CFrame = cf }),
	}
	local h = inner / 2
	local turn = math.rad(45)
	for _, a in { -1, 1 } do
		for _, c in { -1, 1 } do
			table.insert(
				parts,
				newPart({
					Size = Vector3.new(inner.X, d, d),
					CFrame = cf * CFrame.new(0, a * h.Y, c * h.Z) * CFrame.Angles(turn, 0, 0),
				})
			)
			table.insert(
				parts,
				newPart({
					Size = Vector3.new(d, inner.Y, d),
					CFrame = cf * CFrame.new(a * h.X, 0, c * h.Z) * CFrame.Angles(0, turn, 0),
				})
			)
			table.insert(
				parts,
				newPart({
					Size = Vector3.new(d, d, inner.Z),
					CFrame = cf * CFrame.new(a * h.X, c * h.Y, 0) * CFrame.Angles(0, 0, turn),
				})
			)
		end
	end
	return parts
end

-- An ellipsoid filling `size` at `cf`.
local function ellipsoid(cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = newPart({ Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A crystal shard standing on `cf` (its foot), `width` thick and `height` tall: a square prism with a pyramid point.
local function shard(cf: CFrame, width: number, height: number): { BasePart }
	local body = height * 0.68
	local tip = height - body
	local parts = { newPart({ Size = Vector3.new(width, body, width), CFrame = cf * CFrame.new(0, body / 2, 0) }) }
	-- The point: four corner wedges, each turned so its peak (a corner wedge's +X -Z corner) is in the middle.
	for k = 0, 3 do
		local quarter = cf
			* CFrame.new(0, body + tip / 2, 0)
			* CFrame.Angles(0, math.rad(90 * k), 0)
			* CFrame.new(width / 4, 0, width / 4)
			* CFrame.Angles(0, math.rad(90), 0)
		table.insert(
			parts,
			newPart({ Size = Vector3.new(width / 2, tip, width / 2), CFrame = quarter }, "CornerWedgePart")
		)
	end
	return parts
end

-- `parts` joined into one part of `color` and `material` in `parent`, with `cuts` taken out of it; if that fails, the
-- parts themselves.
local function solid(
	parent: Instance,
	name: string,
	parts: { BasePart },
	color: Color3,
	material: Enum.Material,
	cuts: { BasePart }?
): BasePart
	for _, p in parts do
		p.Color = color
		p.Material = material
		p.Parent = parent
	end
	local options = {
		CollisionFidelity = Enum.CollisionFidelity.Box,
		RenderFidelity = Enum.RenderFidelity.Precise,
		SplitApart = false,
	}
	local first = parts[1]
	local rest = table.move(parts, 2, #parts, 1, {})
	local ok, result = pcall(function()
		local union = GeometryService:UnionAsync(first, rest, options)[1]
		if cuts and #cuts > 0 then
			for _, cut in cuts do
				cut.Parent = parent
			end
			union.Parent = parent
			local carved = GeometryService:SubtractAsync(union, cuts, options)[1]
			for _, cut in cuts do
				cut:Destroy()
			end
			union:Destroy()
			union = carved
		end
		return union
	end)
	if not ok or not result then
		warn("[MinionModel] union failed, keeping the parts:", result)
		first.Name = name
		return first
	end
	for _, p in parts do
		p:Destroy()
	end
	local union = result :: BasePart
	union.Name = name;
	(union :: any).UsePartColor = true
	union.Color = color
	union.Material = material
	union.Anchored = true
	union.CanCollide = false
	union.CanQuery = false
	union.CanTouch = false
	union.Parent = parent
	return union
end

local function darker(color: Color3, by: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, v * (1 - by))
end

-- A crack on a face: a jagged line of thin dark slivers through `points` (in `face`'s space, on its surface).
local function crack(parent: Instance, face: CFrame, points: { Vector2 }, color: Color3)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local middle = (a + b) / 2
		local length = (b - a).Magnitude
		local angle = math.atan2(b.Y - a.Y, b.X - a.X)
		newPart({
			Name = "Crack",
			Size = Vector3.new(length + 0.08, 0.1, 0.05),
			CFrame = face * CFrame.new(middle.X, middle.Y, 0.01) * CFrame.Angles(0, 0, angle),
			Color = color,
			CastShadow = false,
		}).Parent =
			parent
	end
end

-- One minion of `kind` for `team`, unparented, at the origin.
local function build(team: string, kind: Kind): Model
	local stone = STONE[team] or Config.Teams[team].DarkColor
	local glow = CRYSTAL[team] or Config.Teams[team].Color
	local spitter = kind == "Spitter"
	local model = Instance.new("Model")
	model.Name = "Rock" .. kind

	local centre = CFrame.new(0, BODY_LIFT + BODY.Y / 2, 0)
	local front = -BODY.Z / 2
	local half = BODY / 2

	-- The body with its ears and feet, one union, with chips knocked out of a few edges.
	local pieces = bevelledBox(centre, BODY, BEVEL)
	for _, side in { -1, 1 } do
		local ear = centre * CFrame.new(side * (half.X - 0.62), half.Y + 0.42, 0.3)
		for _, p in bevelledBox(ear, Vector3.new(0.9, 1.15, 0.85), 0.14) do
			table.insert(pieces, p)
		end
		for _, z in { -1, 1 } do
			local foot = CFrame.new(side * (half.X - 0.6), 0.42, z * (half.Z - 0.6))
			for _, p in bevelledBox(foot, Vector3.new(1.1, 0.84, 1.2), 0.14) do
				table.insert(pieces, p)
			end
		end
	end
	local chips = {}
	for _, spot in
		{
			{ Vector3.new(-half.X, half.Y, -half.Z), Vector3.new(30, 20, 15) },
			{ Vector3.new(half.X, -half.Y * 0.2, -half.Z), Vector3.new(10, 45, 30) },
			{ Vector3.new(half.X, half.Y, half.Z * 0.3), Vector3.new(40, 10, 25) },
			{ Vector3.new(-half.X, -half.Y * 0.7, half.Z), Vector3.new(20, 35, 40) },
		}
	do
		local turn = CFrame.Angles(math.rad(spot[2].X), math.rad(spot[2].Y), math.rad(spot[2].Z))
		table.insert(chips, newPart({ Size = Vector3.one * 0.7, CFrame = centre * CFrame.new(spot[1]) * turn }))
	end
	local body = solid(model, "Body", pieces, stone, STONE_MATERIAL, chips)
	model.PrimaryPart = body

	-- Cracks over the front and the sides, kept inside the bevels.
	local crackColor = darker(stone, 0.45)
	local faceFront = centre * CFrame.new(0, 0, front)
	crack(model, faceFront, { Vector2.new(-1.3, 1.45), Vector2.new(-1.0, 1.15), Vector2.new(-1.15, 0.85) }, crackColor)
	crack(model, faceFront, { Vector2.new(1.3, -0.35), Vector2.new(1.05, -0.7), Vector2.new(1.2, -1.05) }, crackColor)
	local faceLeft = centre * CFrame.new(-half.X, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	crack(model, faceLeft, { Vector2.new(-0.9, 1.4), Vector2.new(-0.5, 0.95), Vector2.new(-0.7, 0.4) }, crackColor)
	crack(model, faceLeft, { Vector2.new(0.5, -0.2), Vector2.new(0.9, -0.7), Vector2.new(0.75, -1.25) }, crackColor)
	local faceBack = centre * CFrame.new(0, 0, half.Z) * CFrame.Angles(0, math.rad(180), 0)
	crack(model, faceBack, { Vector2.new(-0.4, 1.4), Vector2.new(0.05, 0.9), Vector2.new(-0.2, 0.3) }, crackColor)

	-- The face: white eyes under heavy stone brows, a dark mouth with two fangs above and two teeth below.
	for _, side in { -1, 1 } do
		local eye = faceFront * CFrame.new(side * 0.76, 0.36, -0.02)
		ellipsoid(eye, Vector3.new(1.0, 1.06, 0.5), EYE_WHITE).Parent = model
		local pupil = eye * CFrame.new(-side * 0.13, -0.05, -0.22)
		ellipsoid(pupil, Vector3.new(0.48, 0.54, 0.16), PUPIL).Parent = model
		ellipsoid(pupil * CFrame.new(side * 0.1, 0.13, -0.06), Vector3.one * 0.14, EYE_WHITE, Enum.Material.Neon).Parent =
			model
		local brow = faceFront * CFrame.new(side * 0.78, 1.02, -0.22) * CFrame.Angles(0, 0, math.rad(side * 22))
		solid(model, "Brow", bevelledBox(brow, Vector3.new(1.2, 0.4, 0.46), 0.1), darker(stone, 0.12), STONE_MATERIAL)
	end
	local mouth = faceFront * CFrame.new(0, -0.68, -0.02)
	solid(model, "Mouth", bevelledBox(mouth, Vector3.new(2.05, 1.0, 0.1), 0.08), MOUTH, Enum.Material.SmoothPlastic)
	for _, side in { -1, 1 } do
		newPart({
			Name = "Fang",
			Size = Vector3.new(0.26, 0.34, 0.1),
			CFrame = mouth * CFrame.new(side * 0.6, 0.3, -0.06),
			Color = FANG,
		}).Parent =
			model
		newPart({
			Name = "Tooth",
			Size = Vector3.new(0.3, 0.3, 0.1),
			CFrame = mouth * CFrame.new(side * 0.32, -0.33, -0.06),
			Color = FANG,
		}).Parent =
			model
	end

	-- The crystals: a cluster on the head between the ears and one in the right side; the spitter's are bigger.
	local grow = if spitter then 1.55 else 1.2
	local top = centre * CFrame.new(0, half.Y - 0.25, 0.15)
	-- Each shard is glossy glass round a glowing core, so it has facets and light.
	local shards, cores = {}, {}
	for _, s in
		{
			{ Vector3.new(0, 0, 0), Vector3.new(0, 45, 0), 0.55, 1.6 },
			{ Vector3.new(-0.36, 0, 0.1), Vector3.new(0, 20, 24), 0.42, 1.05 },
			{ Vector3.new(0.34, 0, -0.05), Vector3.new(0, -30, -22), 0.4, 0.95 },
			{ Vector3.new(0.05, 0, 0.4), Vector3.new(-26, 40, 0), 0.34, 0.8 },
		}
	do
		local at = top * CFrame.new(s[1] * grow) * CFrame.Angles(math.rad(s[2].X), math.rad(s[2].Y), math.rad(s[2].Z))
		for _, p in shard(at, s[3] * grow, s[4] * grow) do
			table.insert(shards, p)
		end
		for _, p in shard(at, s[3] * grow * 0.5, s[4] * grow * 0.85) do
			table.insert(cores, p)
		end
	end
	local crystal = solid(model, "Crystal", shards, glow, Enum.Material.Glass)
	crystal.Transparency = 0.3
	solid(model, "CrystalCore", cores, glow:Lerp(Color3.new(1, 1, 1), 0.25), Enum.Material.Neon)
	local side = centre * CFrame.new(half.X - 0.05, -0.1, 0.1) * CFrame.Angles(0, math.rad(90), 0)
	local inlay = {}
	for _, s in { { 0, 0.2, 0.55, 1.1 }, { -0.35, -0.35, 0.38, 0.75 }, { 0.32, -0.3, 0.32, 0.6 } } do
		local at = side * CFrame.new(s[1] * grow, s[2] * grow, 0) * CFrame.Angles(0, 0, math.rad(45))
		table.insert(
			inlay,
			newPart({ Size = Vector3.new(s[3] * grow, s[4] * grow, 0.2) * Vector3.new(0.75, 1, 1), CFrame = at })
		)
	end
	solid(model, "SideCrystal", inlay, glow, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = if spitter then 9 else 5
	light.Brightness = if spitter then 1.1 else 0.6
	light.Shadows = false
	light.Parent = crystal

	-- Only the body is anchored; everything else hangs on it, so moving the body moves the minion.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = d
			weld.Parent = d
			d.Anchored = false
			d.Massless = true
		end
	end
	body.PivotOffset = body.CFrame:ToObjectSpace(CFrame.new(0, 0, 0))
	return model
end

local templates: { [string]: Model } = {}

-- A new minion of `kind` for `team`, unparented, with its pivot (bottom centre) at the origin.
function MinionModel.new(team: string, kind: Kind): Model
	local key = team .. kind
	if not templates[key] then
		templates[key] = build(team, kind)
	end
	return templates[key]:Clone()
end

-- Every team's and kind's template in ReplicatedStorage.MinionTemplates, named team then kind ("RedSpitter"), for
-- the clients to show the minions with; with each team's crystal colour as the folder's attribute "<team>Glow".
function MinionModel.publish(): Folder
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local existing = ReplicatedStorage:FindFirstChild("MinionTemplates")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "MinionTemplates"
	for _, team in Config.TeamOrder do
		folder:SetAttribute(team .. "Glow", CRYSTAL[team] or Config.Teams[team].Color)
		for _, kind: Kind in { "Melee", "Spitter" } do
			local model = MinionModel.new(team, kind)
			model.Name = team .. kind
			model.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
	return folder
end

return MinionModel
