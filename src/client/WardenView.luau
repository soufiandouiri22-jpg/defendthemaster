-- The wardens' eyes and beams (Config.Wardens, the server's WardenService). A knight statue's eyes are dark stone
-- until a living enemy hero who is not hidden comes within Warn studs of its half of the zone, and glow redder as he
-- comes nearer, full at its edge. When it takes a target (Net.Wardens) its eyes flare and the laser's burst sounds as
-- they gather their light; then a red beam goes from each eye to the target and stays on him, following him, with the
-- laser's full sound looping, until the server lets him go. Then the beams fade, the sound dies away and the eyes go
-- back to how near the nearest enemy hero is.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Preferences = require(script.Parent.Preferences)

local WardenView = {}

local SETTINGS = Config.Wardens
local ZONE = Config.Master.Zone
local RED = Color3.fromRGB(255, 0, 0)
-- The eyes asleep, as dark as the stone deep in the visor.
local DARK = Color3.fromRGB(28, 22, 20)
-- How many times brighter the eyes' glow grows while they burn someone, and how fast they follow what they should
-- show (about all of it within Charge).
local FLARE, EASE = 2.5, 6
-- The glow where the beams strike: how wide, how bright.
local SPOT_SIZE, SPOT_BRIGHTNESS = 2.4, 6
-- How much the beams' width trembles, and how fast.
local TREMBLE, TREMBLE_SPEED = 0.12, 38
-- The sound's loudness, the distance it stays full to and the one it is gone at, and how fast it dies away: soft, and
-- only heard near the beam, not across the arena (owner, 2026-11-25). Its loop is loud and steady, so at 0.15 it is
-- about as loud on average as a hero's own sounds (their cues at 0.35 to 0.5), measured by PlaybackLoudness.
local VOLUME, NEAR, FAR, HUSH = 0.15, 10, 60, 0.3

type Burning = {
	hit: Attachment,
	beams: { Beam },
	sound: Sound,
	follow: RBXScriptConnection,
}

-- Each eye's glow (the attachment before it in ColosseumBuilder), by statue (its "Warden" attribute, as "BlueLeft").
local eyes: { [string]: { Attachment } } = {}
local burning: { [string]: Burning } = {}
-- Every warden told of in Net.Wardens, and how bright its eyes are now.
local watched: { [string]: true } = {}
local shine: { [string]: number } = {}

local function eyesOf(warden: string): { Attachment }
	local found = eyes[warden]
	if found and #found > 0 and found[1].Parent then
		return found
	end
	found = {}
	local map = Workspace:FindFirstChild("Map")
	local base = map and map:FindFirstChild((warden:match("^%u%l+") or "") .. "Base")
	for _, part in if base then base:GetDescendants() else {} do
		local statue = part.Parent
		if part.Name == "Eye" and part:IsA("BasePart") and statue and statue:GetAttribute("Warden") == warden then
			local glow = part:FindFirstChildOfClass("Attachment")
			if glow then
				table.insert(found, glow)
			end
		end
	end
	eyes[warden] = found
	-- New eyes (a new map) are as ColosseumBuilder lit them, till they are lit again.
	shine[warden] = nil
	return found
end

local function pointOf(target: Instance): Vector3?
	if not target.Parent then
		return nil
	end
	if target:IsA("BasePart") then
		return target.Position
	elseif target:IsA("Model") then
		local root = target.PrimaryPart
		return if root then root.Position else target:GetPivot().Position
	end
	return nil
end

-- The base `thing` was made with, by ColosseumBuilder, of its `property`.
local function base(thing: Instance, property: string): number
	local name = "Base" .. property
	local was = thing:GetAttribute(name)
	if was == nil then
		was = (thing :: any)[property]
		thing:SetAttribute(name, was)
	end
	return was
end

-- The eyes `glows` shine `times` as bright as ColosseumBuilder made them: dark at 0, red from there to full at 1.
local function light(glows: { Attachment }, times: number)
	local lit = math.min(times, 1)
	for _, glow in glows do
		local fill = glow.Parent
		if fill and fill:IsA("BasePart") then
			fill.Color = DARK:Lerp(RED, lit)
			local face = fill:FindFirstChildOfClass("SurfaceGui")
			if face then
				face.Enabled = lit > 0
				face.Brightness = base(face, "Brightness") * lit
			end
		end
		for _, particles in glow:GetChildren() do
			if particles:IsA("ParticleEmitter") then
				particles.Enabled = lit > 0
				particles.Brightness = base(particles, "Brightness") * times
			end
		end
	end
end

-- How awake the warden `warden` (its statue `statue`) is: from 0 with no enemy hero within Warn studs of its half of
-- the zone to 1 with one at its edge.
local function nearness(warden: string, statue: Instance): number
	local front, half = statue:GetAttribute("Front"), statue:GetAttribute("Half")
	if typeof(front) ~= "Vector3" or typeof(half) ~= "Vector3" then
		return 0
	end
	local team = warden:match("^%u%l+")
	local most = 0
	for _, model in CollectionService:GetTagged("Combatant") do
		if
			model:IsA("Model")
			and model:GetAttribute("Hero")
			and model:GetAttribute("Team") ~= team
			and not model:GetAttribute("Hidden")
		then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local away = model:GetPivot().Position - front
			away = Vector3.new(away.X, 0, away.Z)
			if humanoid and humanoid.Health > 0 and away:Dot(half) >= 0 then
				most = math.max(most, math.clamp((ZONE + SETTINGS.Warn - away.Magnitude) / SETTINGS.Warn, 0, 1))
			end
		end
	end
	return most
end

local function wake(warden: string, dt: number)
	local glows = eyesOf(warden)
	local statue = glows[1] and glows[1].Parent and glows[1].Parent.Parent
	if not statue then
		return
	end
	local want = if burning[warden] then FLARE else nearness(warden, statue)
	local was = shine[warden]
	local now = if was then was + (want - was) * math.min(dt * EASE, 1) else want
	if math.abs(now - want) < 0.005 then
		now = want
	end
	if now ~= was then
		shine[warden] = now
		light(glows, now)
	end
end

-- A beam from `from` to `to`, `wide` times as wide as the core and `bright` as bright as it.
local function beam(from: Attachment, to: Attachment, wide: number, bright: number): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = from
	b.Attachment1 = to
	b.Color = ColorSequence.new(RED)
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Brightness = SETTINGS.Brightness * bright
	b.Width0 = SETTINGS.Width[1] * wide
	b.Width1 = SETTINGS.Width[2] * wide
	b.FaceCamera = true
	b.Segments = 1
	b.Transparency = NumberSequence.new(1)
	b:SetAttribute("Width0", b.Width0)
	b:SetAttribute("Width1", b.Width1)
	b:SetAttribute("Clear", if wide > 1 then 0.6 else 0)
	b.Parent = to
	return b
end

local function spot(at: Attachment)
	local p = Instance.new("ParticleEmitter")
	p.Texture = Assets.GunGlow
	p.Color = ColorSequence.new(RED)
	p.LightEmission = 1
	p.LightInfluence = 0
	p.Brightness = SPOT_BRIGHTNESS
	p.Size = NumberSequence.new(SPOT_SIZE, SPOT_SIZE * 0.5)
	p.Transparency = NumberSequence.new(0.3, 1)
	p.Lifetime = NumberRange.new(0.15)
	p.Speed = NumberRange.new(0)
	p.Rotation = NumberRange.new(0, 360)
	p.Rate = 40
	p.LockedToPart = true
	p.Enabled = false
	p.Parent = at
	return p
end

local function sound(at: Attachment): Sound
	local s = Instance.new("Sound")
	s.SoundId = Assets.WardenLaser
	s.SoundGroup = Preferences.group("Effects")
	s.Volume = VOLUME
	s.Looped = true
	s.PlaybackRegionsEnabled = true
	s.LoopRegion = NumberRange.new(Assets.WardenLaserLoop[1], Assets.WardenLaserLoop[2])
	s.RollOffMode = Enum.RollOffMode.Linear
	s.RollOffMinDistance = NEAR
	s.RollOffMaxDistance = FAR
	s.Parent = at
	s:Play()
	return s
end

local function stop(warden: string)
	local was = burning[warden]
	if not was then
		return
	end
	burning[warden] = nil
	was.follow:Disconnect()
	for _, b in was.beams do
		TweenService:Create(b, TweenInfo.new(SETTINGS.Fade), { Width0 = 0, Width1 = 0 }):Play()
	end
	for _, p in was.hit:GetChildren() do
		if p:IsA("ParticleEmitter") then
			p.Enabled = false
		end
	end
	TweenService:Create(was.sound, TweenInfo.new(HUSH), { Volume = 0 }):Play()
	Debris:AddItem(was.hit, math.max(SETTINGS.Fade, HUSH) + 0.1)
end

local function begin(warden: string, target: Instance)
	local glows = eyesOf(warden)
	local point = pointOf(target)
	if #glows == 0 or not point then
		return
	end
	local hit = Instance.new("Attachment")
	hit.WorldPosition = point
	hit.Parent = Workspace.Terrain
	local beams = {}
	for _, glow in glows do
		table.insert(beams, beam(glow, hit, SETTINGS.Glow, 0.4))
		table.insert(beams, beam(glow, hit, 1, 1))
	end
	local glowSpot = spot(hit)
	local started = os.clock()
	local on = false
	local follow = RunService.RenderStepped:Connect(function()
		hit.WorldPosition = pointOf(target) or hit.WorldPosition
		local t = os.clock() - started - SETTINGS.Charge
		if t < 0 then
			return
		end
		if not on then
			on = true
			glowSpot.Enabled = true
		end
		local shown = math.min(t / SETTINGS.Fade, 1)
		local tremble = 1 + TREMBLE * math.sin(os.clock() * TREMBLE_SPEED)
		for _, b in beams do
			b.Transparency = NumberSequence.new(1 - shown * (1 - b:GetAttribute("Clear")))
			b.Width0 = b:GetAttribute("Width0") * tremble
			b.Width1 = b:GetAttribute("Width1") * tremble
		end
	end)
	burning[warden] = { hit = hit, beams = beams, sound = sound(hit), follow = follow }
end

local function watch(value: ObjectValue)
	local warden = value.Name
	watched[warden] = true
	local function changed()
		stop(warden)
		local target = value.Value
		if target then
			begin(warden, target)
		end
	end
	value.Changed:Connect(changed)
	changed()
end

function WardenView.start()
	local net = ReplicatedStorage:WaitForChild("Net")
	local wardens = net:WaitForChild("Wardens")
	for _, value in wardens:GetChildren() do
		if value:IsA("ObjectValue") then
			watch(value)
		end
	end
	wardens.ChildAdded:Connect(function(value)
		if value:IsA("ObjectValue") then
			watch(value)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		for warden in watched do
			wake(warden, dt)
		end
	end)
end

return WardenView
