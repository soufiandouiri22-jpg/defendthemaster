-- Builds the team minions, the jelly slimes of concept F (Art/Concepts/Minions/minions_concept_F_slimes.jpg), from
-- Roblox parts: a rounded jelly cube with two ears and four blocky feet, an angry face, and for the spitter a glowing
-- core. The body, ears and feet are one union in the team's colour; the face is welded on. Each model's pivot is its
-- bottom centre and its face looks towards -Z, as the kit's pieces do. Each kind's template is built once and cloned.

local GeometryService = game:GetService("GeometryService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local SlimeModel = {}

export type Kind = "Melee" | "Spitter"

-- The body's size, its corners' radius, and how high it stands on its feet (studs; a hero is about 5.2 tall).
local BODY = Vector3.new(3.4, 3.6, 3.3)
local BODY_RADIUS = 0.55
local BODY_LIFT = 0.6

local EYE_WHITE = Color3.fromRGB(248, 244, 240)
local PUPIL = Color3.fromRGB(24, 18, 18)
local FANG = Color3.fromRGB(246, 222, 214)

-- The jelly's own colours per team: brighter and more saturated than the HP bars' team colours, as in the concept.
local JELLY = {
	Blue = Color3.fromRGB(38, 128, 236),
	Red = Color3.fromRGB(226, 34, 34),
}

local function newPart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		p[key] = value
	end
	return p
end

-- The parts of a box `size` with all edges rounded by `radius`, centred on `cf`: three crossing blocks, a cylinder on
-- each edge and a ball on each corner.
local function roundedBox(cf: CFrame, size: Vector3, radius: number): { BasePart }
	local r = math.min(radius, size.X / 2, size.Y / 2, size.Z / 2)
	local inner = size - Vector3.one * 2 * r
	local parts = {
		newPart({ Size = Vector3.new(size.X, inner.Y, inner.Z), CFrame = cf }),
		newPart({ Size = Vector3.new(inner.X, size.Y, inner.Z), CFrame = cf }),
		newPart({ Size = Vector3.new(inner.X, inner.Y, size.Z), CFrame = cf }),
	}
	local h = inner / 2
	for _, a in { -1, 1 } do
		for _, b in { -1, 1 } do
			-- Edges along X, Y and Z (a cylinder's axis is its X).
			table.insert(
				parts,
				newPart({
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(inner.X, 2 * r, 2 * r),
					CFrame = cf * CFrame.new(0, a * h.Y, b * h.Z),
				})
			)
			table.insert(
				parts,
				newPart({
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(inner.Y, 2 * r, 2 * r),
					CFrame = cf * CFrame.new(a * h.X, 0, b * h.Z) * CFrame.Angles(0, 0, math.rad(90)),
				})
			)
			table.insert(
				parts,
				newPart({
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(inner.Z, 2 * r, 2 * r),
					CFrame = cf * CFrame.new(a * h.X, b * h.Y, 0) * CFrame.Angles(0, math.rad(90), 0),
				})
			)
			for _, c in { -1, 1 } do
				table.insert(
					parts,
					newPart({
						Shape = Enum.PartType.Ball,
						Size = Vector3.one * 2 * r,
						CFrame = cf * CFrame.new(a * h.X, b * h.Y, c * h.Z),
					})
				)
			end
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

-- `parts` joined into one part of `color` in `parent`; if the union fails, the parts themselves.
local function solid(parent: Instance, name: string, parts: { BasePart }, color: Color3): BasePart
	for _, p in parts do
		p.Color = color
		p.Parent = parent
	end
	local first = parts[1]
	local rest = table.move(parts, 2, #parts, 1, {})
	local ok, result = pcall(function()
		return GeometryService:UnionAsync(first, rest, {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
			SplitApart = false,
		})
	end)
	local union = ok and result[1]
	if not union then
		warn("[SlimeModel] union failed, keeping the parts:", result)
		first.Name = name
		return first
	end
	for _, p in parts do
		p:Destroy()
	end
	union.Name = name
	union.UsePartColor = true
	union.Color = color
	union.Anchored = true
	union.CanCollide = false
	union.CanQuery = false
	union.CanTouch = false
	union.Parent = parent
	return union
end

local function darker(color: Color3, by: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.05), v * (1 - by))
end

-- One slime of `kind` for `team`, unparented, at the origin.
local function build(team: string, kind: Kind): Model
	local jelly = JELLY[team] or Config.Teams[team].Color
	local model = Instance.new("Model")
	model.Name = "Slime" .. kind

	local centre = CFrame.new(0, BODY_LIFT + BODY.Y / 2, 0)
	local front = -BODY.Z / 2

	-- The body with its ears and feet, one union.
	local pieces = roundedBox(centre, BODY, BODY_RADIUS)
	for _, side in { -1, 1 } do
		local ear = centre * CFrame.new(side * (BODY.X / 2 - 0.7), BODY.Y / 2 + 0.35, 0.25)
		for _, p in roundedBox(ear, Vector3.new(0.95, 1.2, 0.85), 0.22) do
			table.insert(pieces, p)
		end
		for _, z in { -1, 1 } do
			local foot = CFrame.new(side * (BODY.X / 2 - 0.62), 0.42, z * (BODY.Z / 2 - 0.62))
			for _, p in roundedBox(foot, Vector3.new(1.05, 0.84, 1.15), 0.22) do
				table.insert(pieces, p)
			end
		end
	end
	local body = solid(model, "Body", pieces, jelly)
	-- Roblox's glass keeps the jelly's colour full and adds the glossy highlights of the concept.
	body.Material = Enum.Material.Glass
	model.PrimaryPart = body

	-- The face: white eyes looking in under heavy brows, a dark mouth with two fangs above and two jelly teeth below.
	local face = centre * CFrame.new(0, 0, front)
	for _, side in { -1, 1 } do
		local eye = face * CFrame.new(side * 0.76, 0.38, -0.02)
		ellipsoid(eye, Vector3.new(1.05, 1.12, 0.55), EYE_WHITE).Parent = model
		local pupil = eye * CFrame.new(-side * 0.13, -0.05, -0.24)
		ellipsoid(pupil, Vector3.new(0.5, 0.56, 0.16), PUPIL).Parent = model
		ellipsoid(pupil * CFrame.new(side * 0.1, 0.13, -0.06), Vector3.one * 0.15, EYE_WHITE, Enum.Material.Neon).Parent =
			model
		-- Angry: the brows' inner ends low, pressing on the eyes.
		local brow = face * CFrame.new(side * 0.78, 1.04, -0.2) * CFrame.Angles(0, 0, math.rad(side * 22))
		solid(model, "Brow", roundedBox(brow, Vector3.new(1.15, 0.36, 0.42), 0.14), darker(jelly, 0.08))
	end
	local mouth = face * CFrame.new(0, -0.66, -0.02)
	solid(model, "Mouth", roundedBox(mouth, Vector3.new(2.05, 1.02, 0.1), 0.14), darker(jelly, 0.62))
	for _, side in { -1, 1 } do
		newPart({
			Name = "Fang",
			Size = Vector3.new(0.26, 0.36, 0.1),
			CFrame = mouth * CFrame.new(side * 0.6, 0.3, -0.06),
			Color = FANG,
		}).Parent =
			model
		local tooth = mouth * CFrame.new(side * 0.34, -0.36, -0.07)
		solid(model, "Tooth", roundedBox(tooth, Vector3.new(0.34, 0.34, 0.12), 0.06), jelly)
	end

	-- The spitter glows from within: a bright core behind the face and its light.
	if kind == "Spitter" then
		local core = ellipsoid(
			centre * CFrame.new(0.65, 0.15, front + 0.42),
			Vector3.new(1.7, 1.7, 0.6),
			jelly:Lerp(Color3.new(1, 1, 1), 0.6),
			Enum.Material.Neon
		)
		core.Name = "Core"
		core.Parent = model
		local light = Instance.new("PointLight")
		light.Color = jelly:Lerp(Color3.new(1, 1, 1), 0.3)
		light.Range = 9
		light.Brightness = 1.6
		light.Parent = core
		body.Transparency = 0.22
	end

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = d
			weld.Parent = d
		end
	end
	body.PivotOffset = body.CFrame:ToObjectSpace(CFrame.new(0, 0, 0))
	return model
end

local templates: { [string]: Model } = {}

-- A new slime of `kind` for `team`, unparented, with its pivot (bottom centre) at the origin.
function SlimeModel.new(team: string, kind: Kind): Model
	local key = team .. kind
	if not templates[key] then
		templates[key] = build(team, kind)
	end
	return templates[key]:Clone()
end

return SlimeModel
