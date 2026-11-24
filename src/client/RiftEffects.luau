-- Zahra's ground on the client (her R, a Strike that Rolls, Config.Heroes.Zahra), with nothing that glows: she has no
-- aura (owner, 2026-11-24). The rift her great chakrams cut through the ground as they roll, its torn edges thrown up
-- in the colour of the ground there with dust, and the rocks and dust bursting up where they strike together.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local HeroKit = require(ReplicatedStorage.Shared.HeroKit)

local RiftEffects = {}

local GASH = Color3.fromRGB(26, 20, 16)
local SAND = Color3.fromRGB(190, 158, 112)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
-- How long the rift stays open before it closes up, and how long it takes to.
local OPEN, CLOSE = 2.2, 0.8

local groundRay = RaycastParams.new()
groundRay.FilterType = Enum.RaycastFilterType.Exclude

local function effects(): Folder
	local folder = Workspace:FindFirstChild("Effects") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function piece(cframe: CFrame, size: Vector3, colour: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = colour
	part.Material = material
	part.Parent = effects()
	return part
end

-- The colour and material of the ground under `at`, sand when there is none.
local function groundAt(at: Vector3): (Color3, Enum.Material)
	groundRay.FilterDescendantsInstances = HeroKit.leapIgnore()
	local hit = Workspace:Raycast(at + Vector3.new(0, 2, 0), Vector3.new(0, -6, 0), groundRay)
	if not hit then
		return SAND, Enum.Material.Sand
	end
	if hit.Instance:IsA("Terrain") then
		local ok, colour = pcall(function()
			return (hit.Instance :: Terrain):GetMaterialColor(hit.Material)
		end)
		return if ok then colour else SAND, hit.Material
	end
	return (hit.Instance :: BasePart).Color, hit.Material
end

-- Dust of `colour` thrown off `parent`, `count` at once, `size` studs across at first.
local function dust(parent: BasePart, colour: Color3, size: number, count: number, speed: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE
	emitter.Color = ColorSequence.new(colour)
	emitter.LightEmission = 0
	emitter.LightInfluence = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, size * 2.6),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.7, 1.3)
	emitter.Speed = NumberRange.new(speed * 0.4, speed)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -4, 0)
	emitter.Drag = 3
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.Enabled = false
	emitter.Parent = parent
	emitter:Emit(count)
end

-- A rock of the ground's `colour` and `material` torn up at `at`, `size` across, tipped out away from `away`, which
-- falls back in and sinks as the rift closes.
local function rock(at: Vector3, away: Vector3, size: number, colour: Color3, material: Enum.Material, stay: number)
	local tip = CFrame.fromAxisAngle(Vector3.new(away.Z, 0, -away.X).Unit, math.rad(math.random(20, 45)))
	local stood = CFrame.new(at) * tip * CFrame.Angles(0, math.rad(math.random(0, 90)), 0)
	local part = piece(
		stood * CFrame.new(0, -size, 0),
		Vector3.new(size, size * (0.6 + math.random() * 0.5), size * (0.7 + math.random() * 0.4)),
		colour:Lerp(GASH, 0.15),
		material
	)
	TweenService:Create(part, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = stood * CFrame.new(0, size * 0.15, 0),
	}):Play()
	task.delay(stay, function()
		TweenService:Create(part, TweenInfo.new(CLOSE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = stood * CFrame.new(0, -size * 1.2, 0),
			Transparency = 1,
		}):Play()
		task.delay(CLOSE, part.Destroy, part)
	end)
end

-- The rift a great chakram `width` studs thick cuts through the ground from `from` to `to` (both on the ground) in
-- `duration` seconds: a dark gash opening behind it, its edges torn up in rocks and thrown up in dust as it goes,
-- which stays open a while and then closes up.
function RiftEffects.rift(from: Vector3, to: Vector3, width: number, duration: number)
	local way = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = way.Magnitude
	if length < 1 then
		return
	end
	local along = way.Unit
	local aside = Vector3.new(-along.Z, 0, along.X)
	local steps = math.max(math.floor(length / 1.6), 2)
	local last = from
	for i = 1, steps do
		task.delay(duration * (i - 1) / steps, function()
			local point = from:Lerp(to, i / steps) + aside * (math.random() * 2 - 1) * 0.25
			local colour, material = groundAt(point)
			local span = (point - last).Magnitude
			local mid = (last + point) / 2 + Vector3.new(0, 0.04, 0)
			last = point
			local stay = OPEN + duration * (1 - i / steps)
			local gash = piece(
				CFrame.lookAt(mid, point + Vector3.new(0, 0.04, 0)),
				Vector3.new(width * (0.7 + math.random() * 0.3), 0.08, span + 0.4),
				GASH,
				Enum.Material.Slate
			)
			task.delay(stay, function()
				TweenService
					:Create(gash, TweenInfo.new(CLOSE), { Transparency = 1, Size = gash.Size * Vector3.new(0.1, 1, 1) })
					:Play()
				task.delay(CLOSE, gash.Destroy, gash)
			end)
			for _, out in { 1, -1 } do
				if math.random() < 0.8 then
					local edge = point + aside * out * (width * 0.5 + 0.3 + math.random() * 0.4)
					rock(edge, aside * out, 0.5 + math.random() * 0.5, colour, material, stay)
				end
			end
			local puff = piece(CFrame.new(point), Vector3.new(width, 0.2, width), colour, material)
			puff.Transparency = 1
			dust(puff, colour, 1.1, 3, 6)
			task.delay(1.5, puff.Destroy, puff)
		end)
	end
end

-- Where the chakrams strike together on `ground`, reaching `radius` studs: rocks of the ground thrown up out of it in
-- a ring and a cloud of dust (the slam's ring of dust rolling out comes with it, ShadowEffects.Dust).
function RiftEffects.impact(ground: Vector3, radius: number)
	local colour, material = groundAt(ground)
	local count = math.max(math.floor(radius * 1.4), 8)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.3
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		rock(
			ground + out * radius * (0.35 + math.random() * 0.55),
			out,
			0.7 + math.random() * 0.9,
			colour,
			material,
			1.4
		)
	end
	local cloud = piece(CFrame.new(ground), Vector3.new(radius, 0.3, radius), colour, material)
	cloud.Transparency = 1
	dust(cloud, colour, 1.8, 16, 14)
	task.delay(2, cloud.Destroy, cloud)
end

return RiftEffects
