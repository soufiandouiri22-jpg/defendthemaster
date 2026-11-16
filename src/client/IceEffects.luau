-- Astryn's ice on the client (its R, a Strike that Erupts, Config.Heroes.Astryn), icy blue (owner, 2026-11-14): the
-- frost runes turning on the spot it will strike, the cracks of frost racing through the ground from Astryn to it as
-- its globe goes under, and the pillar of ice crystals bursting up out of the ground there, which stands while Astryn
-- holds it up and then shatters.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local UiSound = require(script.Parent.UiSound)

local IceEffects = {}

local MAIN = Color3.fromRGB(120, 210, 255)
local PALE = Color3.fromRGB(200, 238, 255)
local WHITE = Color3.fromRGB(240, 252, 255)
local DEEP = Color3.fromRGB(28, 70, 110)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

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
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Parent = gui
	gui.Parent = part
	return part, label
end

-- Frost glinting and mist off `parent`, `count` at once or `rate` a second.
local function frost(parent: Instance, size: number, speed: NumberRange, count: number?, rate: number?): ParticleEmitter
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = SPARK
	sparkles.Color = ColorSequence.new(WHITE, MAIN)
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Lifetime = NumberRange.new(0.4, 0.9)
	sparkles.Speed = speed
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Acceleration = Vector3.new(0, -12, 0)
	sparkles.Drag = 2
	sparkles.Rate = rate or 0
	sparkles.Enabled = rate ~= nil
	sparkles.Parent = parent
	if count then
		sparkles:Emit(count)
	end
	return sparkles
end

local function mist(parent: Instance, size: number, count: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE
	emitter.Color = ColorSequence.new(PALE, MAIN)
	emitter.LightEmission = 0.4
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 2.5) })
	emitter.Transparency = NumberSequence.new(0.35, 1)
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(size * 3, size * 6)
	emitter.Drag = 4
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Enabled = false
	emitter.Parent = parent
	emitter:Emit(count)
end

-- The warning on `ground` that the ice bursts up there, reaching `radius` studs, in `duration` seconds: a circle of
-- frost runes turning ever faster over a pale glow, a ring round it, and frost glinting round its edge.
function IceEffects.warn(ground: Vector3, radius: number, duration: number)
	local glow, glowLabel = decal(ground, Assets.IndicatorDisc, DEEP, 0.8, radius * 2)
	local ring, ringLabel = decal(ground + Vector3.new(0, 0.02, 0), Assets.IndicatorRing, MAIN, 0.25, radius * 2)
	local runes, runesLabel = decal(ground + Vector3.new(0, 0.04, 0), Assets.PadRunes, PALE, 0.2, radius * 1.7)
	local edge = holder(ground + Vector3.new(0, 0.4, 0), Vector3.new(radius * 2, 0.5, radius * 2))
	local glint = frost(edge, 0.35, NumberRange.new(1, 3), nil, 35)
	glint.Shape = Enum.ParticleEmitterShape.Cylinder
	glint.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	glint.Acceleration = Vector3.new(0, 4, 0)
	local light = Instance.new("PointLight")
	light.Color = MAIN
	light.Range = radius * 1.5
	light.Brightness = 0.4
	light.Parent = edge
	TweenService:Create(light, TweenInfo.new(duration), { Brightness = 2.2 }):Play()
	TweenService:Create(glowLabel, TweenInfo.new(duration), { ImageTransparency = 0.5 }):Play()
	TweenService:Create(ringLabel, TweenInfo.new(duration), { ImageTransparency = 0 }):Play()

	local started = os.clock()
	local last = started
	local turned = 0
	task.spawn(function()
		while os.clock() - started < duration do
			local now = os.clock()
			local f = (now - started) / duration
			turned += (now - last) * (60 + 420 * f * f)
			last = now
			runesLabel.Rotation = turned
			task.wait()
		end
		glow:Destroy()
		ring:Destroy()
		runes:Destroy()
		edge:Destroy()
	end)
end

-- Frost racing through the ground from `from` to `to` (both on the ground) in `duration` seconds: jagged slivers of
-- glowing ice along its way with small shards poking up, which melt away after.
function IceEffects.crack(from: Vector3, to: Vector3, duration: number)
	local way = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local length = way.Magnitude
	if length < 1 then
		return
	end
	local along = way.Unit
	local aside = Vector3.new(-along.Z, 0, along.X)
	local steps = math.max(math.floor(length / 2.2), 2)
	local last = from
	for i = 1, steps do
		task.delay(duration * (i - 1) / steps, function()
			local point = from:Lerp(to, i / steps) + aside * (math.random() * 2 - 1) * 0.9
			local piece = (point - last).Magnitude
			local mid = (last + point) / 2 + Vector3.new(0, 0.08, 0)
			last = point
			local sliver = holder(mid, Vector3.new(0.35, 0.12, piece + 0.3))
			sliver.CFrame = CFrame.lookAt(mid, point + Vector3.new(0, 0.08, 0))
			sliver.Material = Enum.Material.Neon
			sliver.Color = MAIN
			sliver.Transparency = 0.1
			local shard = holder(point, Vector3.new(0.5, 1.4, 0.5))
			shard.Material = Enum.Material.Glass
			shard.Color = PALE
			shard.Transparency = 0.2
			shard.CFrame = CFrame.new(point)
				* CFrame.Angles(
					math.rad(math.random(-25, 25)),
					math.rad(math.random(0, 90)),
					math.rad(math.random(-25, 25))
				)
				* CFrame.new(0, -0.7, 0)
			TweenService:Create(shard, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				CFrame = shard.CFrame * CFrame.new(0, 1, 0),
			}):Play()
			frost(shard, 0.3, NumberRange.new(2, 5), 6)
			local melt = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.9)
			TweenService:Create(sliver, melt, { Transparency = 1 }):Play()
			TweenService:Create(shard, melt, { Transparency = 1, Size = Vector3.new(0.1, 0.3, 0.1) }):Play()
			task.delay(1.6, function()
				sliver:Destroy()
				shard:Destroy()
			end)
		end)
	end
end

-- The flash of frost where the globe splits into its seeking shots at `at` (its E): a bright ball swelling and
-- fading, a ring of frost racing out round it, and glinting thrown all round.
function IceEffects.split(at: Vector3, colour: Color3)
	local flash = holder(at, Vector3.one * 1.5)
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = WHITE
	flash.Transparency = 0.1
	local quick = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(flash, quick, { Size = Vector3.one * 6, Transparency = 1, Color = colour }):Play()
	local light = Instance.new("PointLight")
	light.Color = colour
	light.Range = 16
	light.Brightness = 5
	light.Parent = flash
	TweenService:Create(light, TweenInfo.new(0.35), { Brightness = 0 }):Play()
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(2, 2)
	gui.LightInfluence = 0
	gui.Adornee = flash
	local ring = Instance.new("ImageLabel")
	ring.BackgroundTransparency = 1
	ring.Image = Assets.IndicatorRing
	ring.ImageColor3 = PALE
	ring.Size = UDim2.fromScale(1, 1)
	ring.Parent = gui
	gui.Parent = flash
	TweenService:Create(gui, quick, { Size = UDim2.fromScale(10, 10) }):Play()
	TweenService:Create(ring, quick, { ImageTransparency = 1 }):Play()
	frost(flash, 0.5, NumberRange.new(10, 22), 40)
	mist(flash, 0.8, 10)
	task.delay(1.2, function()
		flash:Destroy()
	end)
end

-- One crystal of ice, `width` across and `height` long, its foot at `foot`, leaning by `lean` (a rotation): a clear
-- shaft with a glowing core and a diamond tip. Starts sunk under the ground; returns its parts and its risen place.
local function crystal(foot: Vector3, lean: CFrame, width: number, height: number): ({ BasePart }, { CFrame })
	local base = CFrame.new(foot) * lean
	local shaft = holder(foot, Vector3.new(width, height, width))
	shaft.Material = Enum.Material.Glass
	shaft.Color = PALE
	shaft.Transparency = 0.15
	shaft.Reflectance = 0.15
	local core = holder(foot, Vector3.new(width * 0.45, height * 0.92, width * 0.45))
	core.Material = Enum.Material.Neon
	core.Color = MAIN
	core.Transparency = 0.35
	local tip = holder(foot, Vector3.one * width * 0.72)
	tip.Material = Enum.Material.Glass
	tip.Color = WHITE
	tip.Transparency = 0.1
	local placed = {
		base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, math.rad(45), 0),
		base * CFrame.new(0, height * 0.47, 0) * CFrame.Angles(0, math.rad(45), 0),
		base * CFrame.new(0, height, 0) * CFrame.Angles(math.rad(45), math.rad(45), math.rad(45)),
	}
	local parts = { shaft, core, tip }
	local sunk = CFrame.new(0, -(height + width), 0)
	for i, part in parts do
		part.CFrame = (base * sunk * base:Inverse()) * placed[i]
	end
	return parts, placed
end

-- The pillar of ice bursting up out of `ground`, reaching `radius` studs, `height` tall: a great crystal in the middle
-- and a ring of smaller ones leaning out round it, rising in a moment with a slam of frost; it stands `stand` seconds
-- and then shatters, its crystals flung out and melting into a cloud of frost. Returns the top of the great crystal.
function IceEffects.pillar(ground: Vector3, radius: number, height: number, stand: number): Vector3
	local crystals: { { parts: { BasePart }, placed: { CFrame } } } = {}
	local function add(foot: Vector3, lean: CFrame, width: number, tall: number)
		local parts, placed = crystal(foot, lean, width, tall)
		table.insert(crystals, { parts = parts, placed = placed })
	end
	add(ground, CFrame.Angles(0, math.rad(math.random(0, 90)), 0), 3.2, height)
	local ring = 7
	for i = 1, ring do
		local angle = (i + math.random() * 0.4) / ring * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local foot = ground + out * radius * (0.35 + math.random() * 0.3)
		local lean = CFrame.lookAt(Vector3.zero, out) * CFrame.Angles(-math.rad(25 + math.random() * 20), 0, 0)
		add(foot, lean, 1.4 + math.random() * 0.8, height * (0.3 + math.random() * 0.25))
	end
	local rise = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for _, c in crystals do
		for i, part in c.parts do
			TweenService:Create(part, rise, { CFrame = c.placed[i] }):Play()
		end
	end
	local top = ground + Vector3.new(0, height, 0)
	local burst = holder(ground + Vector3.new(0, 1, 0), Vector3.new(radius, 0.5, radius))
	mist(burst, 2.4, 40)
	frost(burst, 0.7, NumberRange.new(18, 34), 60)
	local light = Instance.new("PointLight")
	light.Color = MAIN
	light.Range = radius * 2.5
	light.Brightness = 4
	light.Parent = burst
	TweenService:Create(light, TweenInfo.new(stand + 0.5), { Brightness = 1.2 }):Play()
	local hum = holder(ground + Vector3.new(0, height / 2, 0), Vector3.new(3, height, 3))
	frost(hum, 0.4, NumberRange.new(1, 3), nil, 30)

	task.delay(stand, function()
		hum:Destroy()
		UiSound.at("IceShatter", ground + Vector3.new(0, height / 2, 0))
		mist(burst, 2, 50)
		frost(burst, 0.6, NumberRange.new(14, 28), 70)
		TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 0 }):Play()
		local fling = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, c in crystals do
			local middle = c.parts[1].Position
			local out = Vector3.new(middle.X - ground.X, 0, middle.Z - ground.Z)
			out = if out.Magnitude > 0.5
				then out.Unit
				else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
			local thrown = out * (4 + math.random() * 4) + Vector3.new(0, 1 + math.random() * 3, 0)
			local spin = CFrame.Angles(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
			for _, part in c.parts do
				TweenService:Create(part, fling, {
					CFrame = (part.CFrame + thrown) * spin,
					Size = part.Size * 0.3,
					Transparency = 1,
				}):Play()
			end
		end
		task.delay(0.7, function()
			for _, c in crystals do
				for _, part in c.parts do
					part:Destroy()
				end
			end
		end)
		task.delay(1.4, function()
			burst:Destroy()
		end)
	end)
	return top
end

return IceEffects
