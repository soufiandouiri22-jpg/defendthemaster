-- Shadowren's shadow magic on the client: the puff where a thrown dagger strikes, the trail of his dash, the shockwave where he lands from his
-- leap (a dark ring racing out over the ground to the edge of its reach, a shadow that fades under it, smoke thrown
-- outwards and a short violet flash), and the larger slam of his ultimate; and the burst of Mavorak's great orb.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)

local ShadowEffects = {}

local SHADOW = Color3.fromRGB(120, 60, 200)
local DEEP = Color3.fromRGB(16, 8, 30)
local BRIGHT = Color3.fromRGB(196, 140, 255)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- The colours of a slam: its outer ring and smoke, the shade it leaves and the smoke's end, its inner ring, sparks and
-- flash, and the `sparks` it throws up (their textures, taken in turn). Shadow by default; Light is Jestrel's white
-- magic (Config's Effects "Light"), throwing up the twinkles and card suits his beams shed (owner, 2026-11-01); Red is
-- Korrund's (Effects "Red", owner 2026-11-03: no violet on him); Blue is the samurai's, her blue aura (Effects "Blue");
-- Dust is Haldrek's, who has no aura (Effects "Dust", owner 2026-11-05): sand and dust thrown up, nothing violet;
-- Wind is plain white wind, for a hero without an aura (Effects "Wind", owner 2026-11-05).
export type Palette = { main: Color3, deep: Color3, bright: Color3, sparks: { string }? }
local SHADOWS: Palette = { main = SHADOW, deep = DEEP, bright = BRIGHT }
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
ShadowEffects.Light = {
	main = Color3.fromRGB(235, 235, 245),
	deep = Color3.fromRGB(205, 205, 215),
	bright = Color3.fromRGB(255, 255, 255),
	sparks = { Assets.CardStar, table.unpack(Assets.CardSuits) },
} :: Palette
ShadowEffects.Red = {
	main = Color3.fromRGB(196, 28, 24),
	deep = Color3.fromRGB(42, 6, 6),
	bright = Color3.fromRGB(255, 112, 72),
} :: Palette
ShadowEffects.Blue = {
	main = Color3.fromRGB(40, 120, 255),
	deep = Color3.fromRGB(6, 16, 44),
	bright = Color3.fromRGB(140, 210, 255),
} :: Palette
ShadowEffects.Dust = {
	main = Color3.fromRGB(190, 158, 112),
	deep = Color3.fromRGB(96, 74, 48),
	bright = Color3.fromRGB(238, 222, 186),
} :: Palette
-- Its shade a cool grey, so the white rings still show on the pale sand.
ShadowEffects.Wind = {
	main = Color3.fromRGB(228, 232, 238),
	deep = Color3.fromRGB(118, 126, 140),
	bright = Color3.fromRGB(255, 255, 255),
} :: Palette

local function effects(): Folder
	local folder = Workspace:FindFirstChild("Effects") :: Folder?
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

-- Throws `count` sparks `size` studs up from `parent` in `colours` (its `sparks` textures shared out between them, or
-- the plain spark), each emitter `setup` first. A palette's own sparks are unlit, so thrown together they do not run
-- into one white blot.
local function throwSparks(
	parent: Instance,
	colours: Palette,
	size: number,
	count: number,
	setup: (ParticleEmitter) -> ()
)
	local textures = colours.sparks or { SPARK }
	for i, texture in textures do
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = texture
		sparks.Color = ColorSequence.new(colours.bright, colours.main)
		sparks.LightEmission = if colours.sparks then 0 else 1
		sparks.LightInfluence = if colours.sparks then 0 else 1
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
		sparks.EmissionDirection = Enum.NormalId.Top
		if colours.sparks then
			sparks.Rotation = NumberRange.new(-25, 25)
		end
		sparks.Enabled = false
		setup(sparks)
		sparks.Parent = parent
		sparks:Emit(count // #textures + (if i <= count % #textures then 1 else 0))
	end
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
	return part
end

local function smoke(
	parent: Instance,
	count: number,
	speed: NumberRange,
	size: NumberSequence,
	life: NumberRange,
	palette: Palette?
)
	local colours = palette or SHADOWS
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE
	emitter.Color = ColorSequence.new(colours.main, colours.deep)
	emitter.LightEmission = 0.3
	emitter.Size = size
	emitter.Transparency = NumberSequence.new(0.15, 1)
	emitter.Lifetime = life
	emitter.Speed = speed
	emitter.Drag = 4
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Enabled = false
	emitter.Parent = parent
	emitter:Emit(count)
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
	part.Parent = effects()
	return part, label
end

-- The puff of shadow where a thrown dagger strikes.
function ShadowEffects.burst(at: Vector3)
	local part = holder(at, Vector3.one)
	part.Parent = effects()
	smoke(
		part,
		18,
		NumberRange.new(6, 12),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3) }),
		NumberRange.new(0.3, 0.5)
	)
	task.delay(1, function()
		part:Destroy()
	end)
end

-- The trail of a dash from `from` to `to` (on the ground) over `duration` seconds: a puff where he leaves, smoke along
-- the way as he passes, and a puff where he arrives; in the colours of `palette` when given.
function ShadowEffects.dash(from: Vector3, to: Vector3, duration: number, palette: Palette?)
	local steps = 6
	for i = 0, steps do
		local alpha = i / steps
		task.delay(duration * alpha, function()
			local part = holder(from:Lerp(to, alpha) + Vector3.new(0, 1.2, 0), Vector3.new(1.5, 1.5, 1.5))
			part.Parent = effects()
			local ends = i == 0 or i == steps
			smoke(
				part,
				if ends then 14 else 6,
				NumberRange.new(2, if ends then 8 else 4),
				NumberSequence.new({
					NumberSequenceKeypoint.new(0, if ends then 1.8 else 1.4),
					NumberSequenceKeypoint.new(1, if ends then 3.5 else 2.6),
				}),
				NumberRange.new(0.35, 0.6),
				palette
			)
			task.delay(1, function()
				part:Destroy()
			end)
		end)
	end
end

-- The shockwave of the leap's landing on the ground at `ground`, reaching `radius` studs; in the colours of `palette`
-- when given.
function ShadowEffects.shockwave(ground: Vector3, radius: number, palette: Palette?)
	local colours = palette or SHADOWS
	local quick = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local slow = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local ring, ringLabel = decal(ground, Assets.IndicatorRing, colours.main, 0, 2)
	TweenService:Create(ring, quick, { Size = Vector3.new(radius * 2.3, 0.05, radius * 2.3) }):Play()
	TweenService:Create(ringLabel, TweenInfo.new(0.5), { ImageTransparency = 1 }):Play()

	local shade, shadeLabel = decal(ground, Assets.IndicatorDisc, colours.deep, 0.05, radius * 2)
	shade.Size = Vector3.new(radius, 0.05, radius)
	TweenService:Create(shade, quick, { Size = Vector3.new(radius * 2, 0.05, radius * 2) }):Play()
	TweenService:Create(shadeLabel, slow, { ImageTransparency = 1 }):Play()

	local centre = holder(ground + Vector3.new(0, 1, 0), Vector3.new(radius, 0.5, radius))
	centre.Parent = effects()
	smoke(
		centre,
		40,
		NumberRange.new(14, 26),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) }),
		NumberRange.new(0.5, 0.9),
		palette
	)
	local light = Instance.new("PointLight")
	light.Color = colours.main
	light.Range = radius * 2
	light.Brightness = 4
	light.Parent = centre
	TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()

	task.delay(1.5, function()
		ring:Destroy()
		shade:Destroy()
		centre:Destroy()
	end)
end

-- The ultimate's slam on the ground at `ground`, reaching `radius` studs: two shockwaves racing out one after the
-- other, a deep shadow left behind, a cloud of smoke, violet sparks thrown up and a bright flash; in the colours of
-- `palette` when given.
function ShadowEffects.slam(ground: Vector3, radius: number, palette: Palette?)
	local colours = palette or SHADOWS
	local quick = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	for i, delay in { 0, 0.12 } do
		task.delay(delay, function()
			local size = radius * (if i == 1 then 2.6 else 1.8)
			local ring, label =
				decal(ground, Assets.IndicatorRing, if i == 1 then colours.main else colours.bright, 0, 2)
			TweenService:Create(ring, quick, { Size = Vector3.new(size, 0.05, size) }):Play()
			TweenService:Create(label, TweenInfo.new(0.6), { ImageTransparency = 1 }):Play()
			task.delay(0.7, function()
				ring:Destroy()
			end)
		end)
	end

	local shade, shadeLabel = decal(ground, Assets.IndicatorDisc, colours.deep, if palette then 0.5 else 0, radius * 2)
	shade.Size = Vector3.new(radius * 0.6, 0.05, radius * 0.6)
	TweenService:Create(shade, quick, { Size = Vector3.new(radius * 2.2, 0.05, radius * 2.2) }):Play()
	TweenService:Create(shadeLabel, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		ImageTransparency = 1,
	}):Play()

	local centre = holder(ground + Vector3.new(0, 1, 0), Vector3.new(radius * 0.8, 0.5, radius * 0.8))
	centre.Parent = effects()
	smoke(
		centre,
		60,
		NumberRange.new(18, 34),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) }),
		NumberRange.new(0.6, 1.1),
		colours
	)
	throwSparks(centre, colours, 0.6, 45, function(sparks)
		sparks.Transparency = NumberSequence.new(0, 0.3)
		sparks.Lifetime = NumberRange.new(0.5, 0.9)
		sparks.Speed = NumberRange.new(20, 38)
		sparks.SpreadAngle = Vector2.new(35, 35)
		sparks.Acceleration = Vector3.new(0, -40, 0)
	end)

	local light = Instance.new("PointLight")
	light.Color = colours.bright
	light.Range = radius * 2
	light.Brightness = 3
	light.Parent = centre
	TweenService:Create(light, TweenInfo.new(0.45), { Brightness = 0 }):Play()

	task.delay(2, function()
		shade:Destroy()
		centre:Destroy()
	end)
end

-- A small wave through the ground at `ground` after a slam, reaching `radius` studs: one thin ring racing out to it and
-- a few sparks, no smoke or flash; in the colours of `palette` when given.
function ShadowEffects.pulse(ground: Vector3, radius: number, palette: Palette?)
	local colours = palette or SHADOWS
	local ring, label = decal(ground, Assets.IndicatorRing, colours.bright, 0.2, 2)
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius * 2, 0.05, radius * 2),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.45), { ImageTransparency = 1 }):Play()

	local centre = holder(ground + Vector3.new(0, 0.5, 0), Vector3.new(1, 0.5, 1))
	centre.Parent = effects()
	throwSparks(centre, colours, 0.4, 12, function(sparks)
		sparks.Lifetime = NumberRange.new(0.3, 0.5)
		sparks.Speed = NumberRange.new(8, 14)
		sparks.SpreadAngle = Vector2.new(60, 60)
		sparks.Acceleration = Vector3.new(0, -30, 0)
	end)

	task.delay(0.6, function()
		ring:Destroy()
		centre:Destroy()
	end)
end

-- A great orb bursting in the air at `at`, reaching `radius` studs: a ball of smoke thrown out every way, violet sparks
-- and a bright flash.
function ShadowEffects.blast(at: Vector3, radius: number)
	local centre = holder(at, Vector3.new(2, 2, 2))
	centre.Parent = effects()
	smoke(
		centre,
		60,
		NumberRange.new(radius * 1.2, radius * 2.4),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) }),
		NumberRange.new(0.5, 0.9)
	)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK
	sparks.Color = ColorSequence.new(BRIGHT, SHADOW)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.4, 0.8)
	sparks.Speed = NumberRange.new(radius * 2, radius * 4)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Drag = 2
	sparks.Enabled = false
	sparks.Parent = centre
	sparks:Emit(60)

	local light = Instance.new("PointLight")
	light.Color = BRIGHT
	light.Range = radius * 2.5
	light.Brightness = 5
	light.Parent = centre
	TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 0 }):Play()

	task.delay(2, function()
		centre:Destroy()
	end)
end

return ShadowEffects
