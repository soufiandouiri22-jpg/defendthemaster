-- Mortael's fire on the client (Config.Heroes[hero].Effects = "Fire"), where Shadowren's shadow would be
-- (ShadowEffects): the trail of his dash, and the shockwave where he lands from a leap. A white-hot flash, two rings of fire racing out over the
-- ground, a fireball thrown up, flames rising round its edge, embers flung out and falling back, dark smoke climbing
-- from the middle, and a scorch mark that glows and slowly cools.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)

local FireEffects = {}

local HOT = Color3.fromRGB(255, 236, 170)
local FLAME = Color3.fromRGB(255, 118, 28)
local EMBER = Color3.fromRGB(200, 40, 10)
local SCORCH = Color3.fromRGB(34, 14, 6)
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local function effects(): Folder
	local folder = Workspace:FindFirstChild("Effects") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function holder(at: Vector3, size: Vector3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.Position = at
	part.Parent = effects()
	return part
end

-- A flat image on the ground at `at`, `size` studs across.
local function decal(at: Vector3, image: string, colour: Color3, transparency: number, size: number): (Part, ImageLabel)
	local part = holder(at + Vector3.new(0, 0.15, 0), Vector3.new(size, 0.05, size))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.Adornee = part
	local label = Instance.new("ImageLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Image = image
	label.ImageColor3 = colour
	label.ImageTransparency = transparency
	label.Parent = gui
	gui.Parent = part
	return part, label
end

local function flames(): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, HOT),
		ColorSequenceKeypoint.new(0.35, FLAME),
		ColorSequenceKeypoint.new(1, EMBER),
	})
end

-- The trail of a dash from `from` to `to` (on the ground) over `duration` seconds: a burst of flame where he leaves,
-- flames and embers along the way as he passes, and a puff of fire where he arrives. No marks on the ground (owner,
-- 2026-10-31: the scorched rings went).
function FireEffects.dash(from: Vector3, to: Vector3, duration: number)
	local steps = 14
	for i = 0, steps do
		local alpha = i / steps
		task.delay(duration * alpha, function()
			local at = from:Lerp(to, alpha)
			local ends = i == 0 or i == steps

			local part = holder(at + Vector3.new(0, 1, 0), Vector3.new(1.5, 1.5, 1.5))
			-- Deeper than the blast's flames: many small ones close together glare white on light ground.
			local fire = Instance.new("ParticleEmitter")
			fire.Texture = FIRE
			fire.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 60)),
				ColorSequenceKeypoint.new(0.4, FLAME),
				ColorSequenceKeypoint.new(1, EMBER),
			})
			fire.LightEmission = 0.6
			fire.LightInfluence = 0
			fire.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, if ends then 2.2 else 1.4),
				NumberSequenceKeypoint.new(0.4, if ends then 3.2 else 2),
				NumberSequenceKeypoint.new(1, 0),
			})
			fire.Transparency =
				NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
			fire.Lifetime = NumberRange.new(0.3, 0.55)
			fire.Speed = NumberRange.new(2, if ends then 9 else 4)
			fire.SpreadAngle = Vector2.new(if ends then 80 else 30, if ends then 80 else 30)
			fire.EmissionDirection = Enum.NormalId.Top
			fire.Acceleration = Vector3.new(0, 10, 0)
			fire.RotSpeed = NumberRange.new(-160, 160)
			fire.Rotation = NumberRange.new(0, 360)
			fire.Enabled = false
			fire.Parent = part
			fire:Emit(if ends then 18 else 4)

			local embers = Instance.new("ParticleEmitter")
			embers.Texture = SPARK
			embers.Color = ColorSequence.new(HOT, FLAME)
			embers.LightEmission = 1
			embers.LightInfluence = 0
			embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
			embers.Lifetime = NumberRange.new(0.5, 0.9)
			embers.Speed = NumberRange.new(5, if ends then 16 else 9)
			embers.SpreadAngle = Vector2.new(60, 60)
			embers.EmissionDirection = Enum.NormalId.Top
			embers.Acceleration = Vector3.new(0, -24, 0)
			embers.Enabled = false
			embers.Parent = part
			embers:Emit(if ends then 16 else 4)

			if ends then
				local light = Instance.new("PointLight")
				light.Color = FLAME
				light.Range = 14
				light.Brightness = 4
				light.Parent = part
				TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 0 }):Play()
			end

			task.delay(1.5, function()
				part:Destroy()
			end)
		end)
	end
end

-- The shockwave of a leap's landing on the ground at `ground`, reaching `radius` studs.
function FireEffects.shockwave(ground: Vector3, radius: number)
	local quick = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

	-- Two rings, white-hot and then flame, the second a little later and further.
	for i, delay in { 0, 0.1 } do
		task.delay(delay, function()
			local size = radius * (if i == 1 then 1.8 else 2.5)
			local ring, label = decal(ground, Assets.IndicatorRing, if i == 1 then HOT else FLAME, 0, 2)
			TweenService:Create(ring, quick, { Size = Vector3.new(size, 0.05, size) }):Play()
			TweenService:Create(label, TweenInfo.new(0.6), { ImageTransparency = 1 }):Play()
			task.delay(0.7, function()
				ring:Destroy()
			end)
		end)
	end

	-- The scorch mark, and over it the ground's glow, which dies first.
	local scorch, scorchLabel = decal(ground, Assets.IndicatorDisc, SCORCH, 0.1, radius * 2)
	scorch.Size = Vector3.new(radius * 0.6, 0.05, radius * 0.6)
	TweenService:Create(scorch, quick, { Size = Vector3.new(radius * 2, 0.05, radius * 2) }):Play()
	TweenService:Create(scorchLabel, TweenInfo.new(2.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		ImageTransparency = 1,
	}):Play()
	local glow, glowLabel = decal(ground + Vector3.new(0, 0.02, 0), Assets.IndicatorDisc, FLAME, 0.35, radius * 1.4)
	glow.Size = Vector3.new(radius * 0.5, 0.05, radius * 0.5)
	TweenService:Create(glow, quick, { Size = Vector3.new(radius * 1.4, 0.05, radius * 1.4) }):Play()
	TweenService:Create(glowLabel, TweenInfo.new(1.2), { ImageTransparency = 1 }):Play()

	local centre = holder(ground + Vector3.new(0, 1, 0), Vector3.new(radius * 0.6, 0.5, radius * 0.6))

	-- The fireball thrown up and out.
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = FIRE
	burst.Color = flames()
	burst.LightEmission = 1
	burst.LightInfluence = 0
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.5),
		NumberSequenceKeypoint.new(0.4, 4.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	burst.Lifetime = NumberRange.new(0.4, 0.8)
	burst.Speed = NumberRange.new(10, 24)
	burst.SpreadAngle = Vector2.new(70, 70)
	burst.EmissionDirection = Enum.NormalId.Top
	burst.Acceleration = Vector3.new(0, 12, 0)
	burst.Drag = 3
	burst.RotSpeed = NumberRange.new(-200, 200)
	burst.Rotation = NumberRange.new(0, 360)
	burst.Enabled = false
	burst.Parent = centre
	burst:Emit(50)

	-- Embers flung out, falling back.
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = SPARK
	embers.Color = ColorSequence.new(HOT, FLAME)
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(0.7, 1.3)
	embers.Speed = NumberRange.new(16, 34)
	embers.SpreadAngle = Vector2.new(45, 45)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Acceleration = Vector3.new(0, -36, 0)
	embers.Enabled = false
	embers.Parent = centre
	embers:Emit(60)

	-- Dark smoke climbing from the middle.
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE
	smoke.Color = ColorSequence.new(Color3.fromRGB(60, 44, 36), Color3.fromRGB(14, 10, 8))
	smoke.LightInfluence = 0.4
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) })
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(1.2, 1.8)
	smoke.Speed = NumberRange.new(4, 10)
	smoke.SpreadAngle = Vector2.new(60, 60)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Acceleration = Vector3.new(0, 4, 0)
	smoke.Drag = 1.5
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.Enabled = false
	smoke.Parent = centre
	smoke:Emit(26)

	-- Flames rising round the edge of the blast for a moment.
	local edge = holder(ground + Vector3.new(0, 0.6, 0), Vector3.new(radius * 1.6, 1, radius * 1.6))
	local wall = Instance.new("ParticleEmitter")
	wall.Texture = FIRE
	wall.Color = flames()
	wall.LightEmission = 1
	wall.LightInfluence = 0
	wall.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(0.4, 2.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	wall.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	wall.Lifetime = NumberRange.new(0.35, 0.6)
	wall.Speed = NumberRange.new(4, 8)
	wall.EmissionDirection = Enum.NormalId.Top
	wall.Acceleration = Vector3.new(0, 10, 0)
	wall.RotSpeed = NumberRange.new(-120, 120)
	wall.Rotation = NumberRange.new(0, 360)
	wall.Shape = Enum.ParticleEmitterShape.Cylinder
	wall.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	wall.Rate = 160
	wall.Parent = edge
	task.delay(0.6, function()
		wall.Enabled = false
	end)

	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = radius * 2.5
	light.Brightness = 6
	light.Parent = centre
	TweenService:Create(light, TweenInfo.new(0.7), { Brightness = 0 }):Play()

	task.delay(2.8, function()
		scorch:Destroy()
		glow:Destroy()
		centre:Destroy()
		edge:Destroy()
	end)
end

return FireEffects
