-- The portals' light (design 03, Config.Portals, PortalService). In each ring's opening a turquoise vortex turns on
-- both faces, its bright arms turning against it, with a rim of light along the stones and a glow that breathes, a
-- light round it and motes drifting out of it either way; on its pad a ring of runes turns slowly. A hero going
-- through (Net.PortalJump) makes both openings flare and throw sparks, rings sweep out over the far pad and a glow
-- fades on him, sounding at both; the player who goes through sees a flash over his screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Portals = require(ReplicatedStorage.Shared.Portals)
local UiSound = require(script.Parent.UiSound)

local PortalView = {}

local GLOW = Color3.fromRGB(120, 240, 250)
local DEEP = Color3.fromRGB(30, 170, 210)
-- The vortex reaches this far past the opening's edge into the stones, so no seam shows.
local TUCK = 0.6
-- The rim's line lies this far out on its picture (Tools/portal_textures.py).
local RIM_LINE = 0.93
-- Seconds a full turn takes: the swirl, its arms (the other way) and the pad's runes.
local SWIRL_TURN, STREAKS_TURN, RUNES_TURN = 7, 3.5, 40
-- The glow's breath: its transparency at rest, how far it swings, and how fast.
local GLOW_REST, GLOW_SWING, GLOW_SPEED = 0.35, 0.12, 2.2
-- The light round the opening: its reach, its brightness at rest, how far its breath swings it, and how much a jump
-- adds; soft, so the ring's grey stones keep their colour (owner, 2026-11-02).
local LIGHT_RANGE, LIGHT_REST, LIGHT_SWING, LIGHT_FLARE = 12, 0.35, 0.1, 2
-- A jump's flare and the far pad's rings: how long they last, and how far the rings reach.
local FLARE, RING_REACH = 0.8, 24
-- The pitch the jump's sound plays at (higher than a hero's coming back on his pad, which uses the same sound).
local JUMP_PITCH = 1.2

type Opening = {
	centre: Vector3,
	top: Vector3,
	glows: { ImageLabel },
	light: PointLight,
	sparks: ParticleEmitter,
	flared: number,
}

local openings: { [string]: Opening } = {}
local runes: { ImageLabel } = {}
local effects: Folder

local function part(name: string, size: Vector3, cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	return p
end

-- A picture on `gui`, `scale` of its width, turning once in `turn` seconds (the other way when negative).
local function layer(gui: SurfaceGui, image: string, scale: number, transparency: number, turn: number, z: number)
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(scale, scale)
	label.Image = image
	label.ImageTransparency = transparency
	label.ZIndex = z
	label.Parent = gui
	if turn ~= 0 then
		local info = TweenInfo.new(math.abs(turn), Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1)
		TweenService:Create(label, info, { Rotation = if turn > 0 then 360 else -360 }):Play()
	end
	return label
end

local function sparkle(size: number, rate: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), GLOW)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Shape = Enum.ParticleEmitterShape.Disc
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.InAndOut
	emitter.Rate = rate
	return emitter
end

local function dress(portal: Portals.Portal)
	local centre = portal.frame * CFrame.new(portal.hole)
	local width = 2 * (portal.holeRadius + TUCK)
	local face = part("PortalVortex", Vector3.new(width, width, 0.05), centre)
	local glows = {}
	local rim = portal.holeRadius / (portal.holeRadius + TUCK) / RIM_LINE
	for _, side in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = side
		gui.LightInfluence = 0
		gui.Brightness = 1.5
		gui.CanvasSize = Vector2.new(512, 512)
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = face
		table.insert(glows, layer(gui, Assets.PortalGlow, 1, GLOW_REST, 0, 1))
		layer(gui, Assets.PortalSwirl, 1, 0.08, SWIRL_TURN, 2)
		layer(gui, Assets.PortalStreaks, 0.96, 0, -STREAKS_TURN, 3)
		layer(gui, Assets.PortalRim, rim, 0, 0, 4)
	end
	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Range = LIGHT_RANGE
	light.Brightness = LIGHT_REST
	light.Parent = face
	face.Parent = effects

	-- Lying in the opening, so the motes and sparks leave it from both faces.
	local disc =
		part("PortalMotes", Vector3.new(width * 0.8, 0.05, width * 0.8), centre * CFrame.Angles(math.rad(90), 0, 0))
	local motes = sparkle(0.3, 10)
	motes.Lifetime = NumberRange.new(1.5, 2.5)
	motes.Speed = NumberRange.new(1, 2.5)
	motes.Acceleration = Vector3.new(0, 0.6, 0)
	motes.Parent = disc
	local sparks = sparkle(0.45, 0)
	sparks.Lifetime = NumberRange.new(0.5, 1)
	sparks.Speed = NumberRange.new(10, 20)
	sparks.SpreadAngle = Vector2.new(35, 35)
	sparks.Acceleration = Vector3.new(0, -12, 0)
	sparks.Parent = disc
	disc.Parent = effects

	local top = portal.frame * Vector3.new(0, portal.top + 0.04, 0)
	local runeWidth = portal.steps[#portal.steps].radius * 1.8
	local plate = part("PortalRunes", Vector3.new(runeWidth, 0.05, runeWidth), CFrame.new(top))
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.LightInfluence = 0
	surface.Brightness = 1.5
	surface.CanvasSize = Vector2.new(512, 512)
	surface.Parent = plate
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Image = Assets.PadRunes
	label.ImageColor3 = GLOW
	label.ImageTransparency = 0.25
	label.Parent = surface
	table.insert(runes, label)
	plate.Parent = effects

	openings[portal.name] = {
		centre = centre.Position,
		top = top,
		glows = glows,
		light = light,
		sparks = sparks,
		flared = -math.huge,
	}
end

local function flare(opening: Opening)
	opening.flared = os.clock()
	opening.sparks:Emit(45)
	UiSound.at("PortalJump", opening.centre, nil, JUMP_PITCH)
end

-- Rings sweeping out over the far pad, and a glow fading on `character`.
local function arrive(opening: Opening, character: Model)
	local info = TweenInfo.new(FLARE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for i, delay in { 0, 0.15 } do
		task.delay(delay, function()
			local ring =
				part("PortalRing", Vector3.new(3, 0.05, 3), CFrame.new(opening.top + Vector3.new(0, 0.05 * i, 0)))
			local surface = Instance.new("SurfaceGui")
			surface.Face = Enum.NormalId.Top
			surface.LightInfluence = 0
			surface.Brightness = 2
			surface.CanvasSize = Vector2.new(512, 512)
			surface.Parent = ring
			local image = Instance.new("ImageLabel")
			image.BackgroundTransparency = 1
			image.Size = UDim2.fromScale(1, 1)
			image.Image = Assets.PadRing
			image.ImageColor3 = GLOW
			image.Parent = surface
			ring.Parent = effects
			local reach = RING_REACH * (if i == 1 then 1 else 0.7)
			TweenService:Create(ring, info, { Size = Vector3.new(reach, 0.05, reach) }):Play()
			TweenService:Create(image, info, { ImageTransparency = 1 }):Play()
			task.delay(FLARE + 0.1, function()
				ring:Destroy()
			end)
		end)
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = GLOW
	highlight.FillTransparency = 0.1
	highlight.OutlineColor = DEEP
	highlight.OutlineTransparency = 0.3
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = character
	TweenService:Create(highlight, info, { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	task.delay(FLARE + 0.2, function()
		highlight:Destroy()
	end)
end

-- A turquoise flash over the player's screen as he goes through.
local function flash()
	local gui = Instance.new("ScreenGui")
	gui.Name = "PortalFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	local cover = Instance.new("Frame")
	cover.Size = UDim2.fromScale(1, 1)
	cover.BorderSizePixel = 0
	cover.BackgroundColor3 = GLOW
	cover.BackgroundTransparency = 0.3
	cover.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	TweenService:Create(cover, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.6, function()
		gui:Destroy()
	end)
end

local function jumped(from: string, to: string, character: Model?)
	local entry, exit = openings[from], openings[to]
	if entry then
		flare(entry)
	end
	if exit then
		flare(exit)
		if character and character.Parent then
			arrive(exit, character)
		end
	end
	if character and character == Players.LocalPlayer.Character then
		flash()
	end
end

local function update(dt: number)
	local now = os.clock()
	for _, label in runes do
		label.Rotation = (label.Rotation + 360 / RUNES_TURN * dt) % 360
	end
	for _, opening in openings do
		local flaring = math.clamp(1 - (now - opening.flared) / FLARE, 0, 1)
		local breath = math.sin(now * GLOW_SPEED) * GLOW_SWING
		for _, glow in opening.glows do
			glow.ImageTransparency = math.clamp(GLOW_REST + breath - flaring * 0.35, 0, 1)
			glow.Size = UDim2.fromScale(1 + flaring * 0.15, 1 + flaring * 0.15)
		end
		opening.light.Brightness = LIGHT_REST + breath / GLOW_SWING * LIGHT_SWING + flaring * LIGHT_FLARE
	end
end

function PortalView.start()
	if not Config.Portals.Enabled then
		return
	end
	effects = Instance.new("Folder")
	effects.Name = "PortalEffects"
	effects.Parent = Workspace
	local map = Workspace:WaitForChild("Map", 30)
	if not map or not map:WaitForChild("Portals", 30) then
		return
	end
	for _, portal in Portals.all() do
		dress(portal)
	end
	local net = ReplicatedStorage:WaitForChild("Net")
	local jump = net:WaitForChild("PortalJump") :: RemoteEvent
	jump.OnClientEvent:Connect(jumped)
	RunService.RenderStepped:Connect(update)
end

return PortalView
