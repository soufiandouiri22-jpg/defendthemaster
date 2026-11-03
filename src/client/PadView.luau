-- The spawn pads' light (design 03), in each pad's team colour. At rest a rune circle turns slowly on the pad's top,
-- with a soft light and motes drifting up. A hero healing on it (Net.PadHeal) stands in a column of light with sparks
-- rising round him, and the player sees his own heals as green numbers (HitFeedback.heal). A hero coming back
-- (Net.HeroSpawned) arrives in a burst: a pillar of light, two rings sweeping out over the ground, sparks, and a glow
-- on him that fades. Both sound where they happen: a soft chime as a hero's healing begins, a sparkling rush as he
-- comes back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local HitFeedback = require(script.Parent.HitFeedback)
local Side = require(script.Parent.Side)
local UiSound = require(script.Parent.UiSound)

local PadView = {}

-- The rune circle covers this much of the pad's width (its inner disc), and turns this many degrees a second.
local RUNE_SHARE, RUNE_TURN = 0.62, 6
-- A healing hero's column, a beam that fades upwards: its height and width, and how long it lingers after the last heal.
local COLUMN_HEIGHT, COLUMN_WIDTH, COLUMN_LINGER = 9, 4.5, 0.4
-- A respawn's pillar height and the rings' widest reach, and how long the burst lasts.
local PILLAR_HEIGHT, RING_REACH, BURST = 40, 26, 0.9
-- A hero's root stands this high over his feet.
local ROOT_HEIGHT = 3

type Healing = {
	base: Part,
	beam: Beam,
	sparks: ParticleEmitter,
	expires: number,
}

local runes: { ImageLabel } = {}
local healing: { [Model]: Healing } = {}
local effects: Folder

local function lightOf(team: string?): Color3
	local colour = Config.Teams[Side.shown(team)].Color
	return colour:Lerp(Color3.new(1, 1, 1), 0.3)
end

local function part(name: string, size: Vector3, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	return p
end

-- A flat, unlit image lying on `p`'s top face.
local function decal(p: Part, image: string, colour: Color3, transparency: number): ImageLabel
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.LightInfluence = 0
	surface.Brightness = 2
	surface.CanvasSize = Vector2.new(512, 512)
	surface.Parent = p
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Image = image
	label.ImageColor3 = colour
	label.ImageTransparency = transparency
	label.Parent = surface
	return label
end

-- A vertical neon cylinder of `height` and `width`, standing on `base`.
local function column(name: string, base: Vector3, height: number, width: number, colour: Color3): Part
	local cf = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local p = part(name, Vector3.new(height, width, width), cf)
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = colour
	return p
end

local function sparkEmitter(colour: Color3): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), colour)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.EmissionDirection = Enum.NormalId.Top
	return emitter
end

local function dressPad(model: Model)
	local box, size = model:GetBoundingBox()
	local colour = lightOf(model:GetAttribute("Team"))
	local width = math.max(size.X, size.Z) * RUNE_SHARE
	local top = box.Position + Vector3.new(0, size.Y / 2 + 0.03, 0)
	local disc = part("PadRunes", Vector3.new(width, 0.05, width), CFrame.new(top))
	disc.Transparency = 1
	table.insert(runes, decal(disc, Assets.PadRunes, colour, 0.1))
	local light = Instance.new("PointLight")
	light.Color = colour
	light.Range = 14
	light.Brightness = 1.2
	light.Parent = disc
	local motes = sparkEmitter(colour)
	motes.Shape = Enum.ParticleEmitterShape.Disc
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Rate = 5
	motes.Lifetime = NumberRange.new(2.5, 4)
	motes.Speed = NumberRange.new(1.5, 3)
	motes.Acceleration = Vector3.new(0, 0.6, 0)
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Parent = disc
	disc.Parent = effects
end

local function feetOf(root: BasePart): Vector3
	return root.Position - Vector3.new(0, ROOT_HEIGHT, 0)
end

local function healed(character: Model, amount: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if character == Players.LocalPlayer.Character then
		HitFeedback.heal(root.Position, amount)
	end
	local h = healing[character]
	if not h then
		local colour = lightOf(character:GetAttribute("Team"))
		local base = part("PadHealing", Vector3.new(3, 0.2, 3), CFrame.new(feetOf(root)))
		base.Transparency = 1
		local bottom = Instance.new("Attachment")
		bottom.Parent = base
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, COLUMN_HEIGHT, 0)
		top.Parent = base
		local beam = Instance.new("Beam")
		beam.Attachment0 = bottom
		beam.Attachment1 = top
		beam.FaceCamera = true
		beam.Width0 = COLUMN_WIDTH
		beam.Width1 = COLUMN_WIDTH * 0.8
		beam.Color = ColorSequence.new(colour, Config.Teams[Side.shown(character:GetAttribute("Team"))].Color)
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(0.5, 0.8),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Parent = base
		local sparks = sparkEmitter(colour)
		sparks.Shape = Enum.ParticleEmitterShape.Disc
		sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		sparks.Rate = 22
		sparks.Lifetime = NumberRange.new(0.8, 1.3)
		sparks.Speed = NumberRange.new(4, 7)
		sparks.Parent = base
		base.Parent = effects
		h = { base = base, beam = beam, sparks = sparks, expires = 0 }
		healing[character] = h
		UiSound.at("PadHeal", root)
	end
	local entry = h :: Healing
	entry.expires = os.clock() + Config.Pads.Tick + COLUMN_LINGER
end

-- The burst of light where `character` appears on his pad, with its sound only when he comes back after dying (`again`).
local function burst(character: Model, again: boolean)
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not root or not character.Parent then
		return
	end
	local colour = lightOf(character:GetAttribute("Team"))
	local feet = feetOf(root)
	local info = TweenInfo.new(BURST, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if again then
		UiSound.at("Respawn", feet)
	end

	local pillar = column("RespawnPillar", feet, PILLAR_HEIGHT, 5, colour)
	pillar.Transparency = 0.25
	pillar.Parent = effects
	local core = column("RespawnCore", feet, PILLAR_HEIGHT, 1.6, Color3.new(1, 1, 1))
	core.Transparency = 0.1
	core.Parent = effects
	for _, p in { pillar, core } do
		TweenService:Create(p, info, { Transparency = 1, Size = Vector3.new(PILLAR_HEIGHT, 0.2, 0.2) }):Play()
	end
	local light = Instance.new("PointLight")
	light.Color = colour
	light.Range = 22
	light.Brightness = 6
	light.Parent = pillar
	TweenService:Create(light, info, { Brightness = 0 }):Play()

	for i, delay in { 0, 0.15 } do
		task.delay(delay, function()
			local ring = part("RespawnRing", Vector3.new(3, 0.05, 3), CFrame.new(feet + Vector3.new(0, 0.08 * i, 0)))
			ring.Transparency = 1
			local image = decal(ring, Assets.PadRing, colour, 0)
			ring.Parent = effects
			local reach = RING_REACH * (if i == 1 then 1 else 0.7)
			TweenService:Create(ring, info, { Size = Vector3.new(reach, 0.05, reach) }):Play()
			TweenService:Create(image, info, { ImageTransparency = 1 }):Play()
			task.delay(BURST + 0.1, function()
				ring:Destroy()
			end)
		end)
	end

	local sparks = sparkEmitter(colour)
	sparks.Shape = Enum.ParticleEmitterShape.Disc
	sparks.Lifetime = NumberRange.new(0.6, 1.1)
	sparks.Speed = NumberRange.new(8, 16)
	sparks.SpreadAngle = Vector2.new(25, 25)
	sparks.Acceleration = Vector3.new(0, -6, 0)
	sparks.Parent = pillar
	sparks:Emit(36)

	local highlight = Instance.new("Highlight")
	highlight.FillColor = colour
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = character
	TweenService:Create(highlight, info, { FillTransparency = 1 }):Play()

	task.delay(BURST + 1.2, function()
		pillar:Destroy()
		core:Destroy()
		highlight:Destroy()
	end)
end

local function update(dt: number)
	for _, label in runes do
		label.Rotation = (label.Rotation + RUNE_TURN * dt) % 360
	end
	local now = os.clock()
	for character, h in healing do
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if now > h.expires or not root or not character.Parent or not humanoid or humanoid.Health <= 0 then
			healing[character] = nil
			h.sparks.Enabled = false
			h.beam.Enabled = false
			task.delay(1.3, function()
				h.base:Destroy()
			end)
		else
			h.base.CFrame = CFrame.new(feetOf(root :: BasePart))
		end
	end
end

function PadView.start()
	effects = Instance.new("Folder")
	effects.Name = "PadEffects"
	effects.Parent = Workspace
	local map = Workspace:WaitForChild("Map", 30)
	if map then
		for _, model in map:GetDescendants() do
			if model:IsA("Model") and model.Name == "SpawnPad" then
				dressPad(model)
			end
		end
	end
	local net = ReplicatedStorage:WaitForChild("Net")
	local heal = net:WaitForChild("PadHeal") :: RemoteEvent
	heal.OnClientEvent:Connect(function(character: Model?, amount: number)
		if character and character.Parent then
			healed(character, amount)
		end
	end)
	local spawned = net:WaitForChild("HeroSpawned") :: RemoteEvent
	spawned.OnClientEvent:Connect(function(character: Model?, again: boolean?)
		if character then
			task.spawn(burst, character, again == true)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return PadView
